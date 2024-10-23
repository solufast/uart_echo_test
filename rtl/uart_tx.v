`timescale 1ns / 10ps

module uart_tx#(
    parameter integer CLOCK_RATE = 200_000_000,
    parameter integer BAUD_RATE  = 9600
)(
    input       clk,            // System clock input
    input       rst_n,          // Active-low asynchronous reset
    input       tx_start,       // Signal to start transmission
    input [7:0] tx_data_in,     // 8-bit data input
    input       parity_en,      // Parity enable signal
    input       parity_mode,    // Parity mode: 0 = even, 1 = odd
    output reg  tx_serial,      // UART serial data output
    output      tx_busy         // Transmitter is busy
);

    wire       baud_clk;
    reg        restart_baud_clk;

    // State encoding
    localparam IDLE         = 3'b000;
    localparam TX_START_BIT = 3'b001;
    localparam TX_DATA_BITS = 3'b010;
    localparam TX_PARITY_BIT= 3'b011;
    localparam TX_STOP_BIT  = 3'b100;

    reg [2:0]  state;               // FSM state register
    reg [7:0]  tx_data;             // Data to be transmitted
    reg [3:0]  bit_index;           // Bit index for data transmission
    reg        parity_bit;          // Calculated parity bit
    reg [3:0]  tx_index_counter;    // Counter to track number of bits transmitted per character

    baud_rate_generator #(
      .CLOCK_RATE(CLOCK_RATE),     // System clock frequency in Hz
      .BAUD_RATE(BAUD_RATE),       // Desired baud rate in bps
      .OVERSAMPLE(1),
      .INITIAL_POLARITY(1'b0)
    )i_baud_clk_gen(
        .clk(clk),                          // System clock input
        .rst_n(rst_n),                      // Active-low asynchronous reset
        .baud_clk(baud_clk),                // 50% duty cycle standard baud rate clock output for Tx module
        .restart_baud_clk(restart_baud_clk) // Restart baud clock generation for every characters sent
    );

    // Synchronize baud_clk to clk domain for edge detection
    reg  baud_clk_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_clk_reg  <= 0;
        end else begin
            baud_clk_reg  <= baud_clk;
        end
    end

    wire baud_clk_rising = ~baud_clk_reg & baud_clk;  // Detect baud clock rising edge

    // Synchronize tx_start to clk domain and detect rising edge
    reg tx_start_reg ;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_start_reg  <= 0;
        end else begin
            tx_start_reg  <= tx_start;
        end
    end

    // Edge detection for tx_start
    wire tx_start_edge = ~tx_start_reg & tx_start;

    // Flag to indicate start request
    reg tx_start_flag;
    
    // Transmitter is busy transmitting if tx_busy is set
    assign tx_busy = (state != IDLE);

    // FSM controlling UART transmission
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            tx_serial      <= 1'b1;  // Idle state of UART line is high
            bit_index      <= 0;
            tx_data        <= 0;
            parity_bit     <= 0;
            tx_start_flag  <= 0;
            tx_index_counter <= 0;
        end else begin
            // Capture tx_start_edge
            if (tx_start_edge) begin
                tx_start_flag <= 1;
            end
            restart_baud_clk  <= 1'b0;

            case (state)
                IDLE: begin
                    tx_serial <= 1'b1;  // Line high during idle
                    tx_index_counter <= 0;
                    if (tx_start_flag) begin
                        tx_start_flag    <= 0;  // Clear the flag
                        tx_data          <= tx_data_in;
                        parity_bit       <= parity_en ? (parity_mode ? ~^tx_data_in : ^tx_data_in) : 1'b0;
                        state            <= TX_START_BIT;
                        bit_index        <= 0;
                        restart_baud_clk <= 1'b1;
                    end
                end

                TX_START_BIT: begin
                    if (baud_clk_rising) begin
                        tx_serial <= 1'b0;  // Send start bit (low)
                        state     <= TX_DATA_BITS;
                        tx_index_counter <= tx_index_counter + 1;
                    end
                end

                TX_DATA_BITS: begin
                    if (baud_clk_rising) begin
                        tx_serial <= tx_data[bit_index];
                        tx_index_counter <= tx_index_counter + 1;
                        if (bit_index == 7) begin
                            bit_index <= 0;  // Reset bit_index
                            if (parity_en)
                                state <= TX_PARITY_BIT;
                            else
                                state <= TX_STOP_BIT;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end
                end

                TX_PARITY_BIT: begin
                    if (baud_clk_rising) begin
                        tx_serial        <= parity_bit;  // Send the parity bit
                        tx_index_counter <= tx_index_counter + 1;
                        state            <= TX_STOP_BIT;
                    end
                end

                TX_STOP_BIT: begin
                    if (baud_clk_rising) begin
                        tx_serial <= 1'b1;  // Send stop bit (high)
                        tx_index_counter <= tx_index_counter + 1;
                        state     <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
