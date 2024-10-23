module uart_rx #(
    parameter integer CLOCK_RATE = 200_000_000,
    parameter integer BAUD_RATE  = 9600
)(
    input  wire       clk,           // System clock input
    input  wire       rst_n,         // Active-low asynchronous reset
    input  wire       rx_serial,     // UART serial data input
    input  wire       db_rx_serial,  // If set, rx_serial will pass through debouncing module
    input  wire       parity_en,     // Enable parity checking
    input  wire       parity_mode,   // Parity mode: 0 = even, 1 = odd
    output reg [7:0]  data_out,      // 8-bit received data output
    output reg        rx_ready,      // Data valid signal
    output reg        frame_error,   // Frame error flag (invalid stop bit)
    output reg        parity_error   // Parity error flag
);

    wire rx_serial_db;
    wire rx_serial_filtered;

    wire       baud_clk;
    reg        restart_baud_clk;

    // State encoding
    localparam IDLE       = 3'b000;
    localparam START_BIT  = 3'b001;
    localparam DATA_BITS  = 3'b010;
    localparam PARITY_BIT = 3'b011;
    localparam STOP_BIT   = 3'b100;

    reg [2:0]  state;               // FSM state register
    reg [3:0]  bit_index;           // Bit index for receiving data
    reg [7:0]  shift_reg;           // Shift register for incoming data
    reg        calculated_parity;   // Calculated parity based on received bits
    reg        parity_bit_sampled;  // Register to hold the sampled parity bit
    reg [3:0]  rx_index_counter;    // Counter to track bit reception
    reg [4:0]  sample_counter;      // Holds sum of bits currently under sample

    // Debounce module (if required)
    debounce #(
        .COUNTER_WIDTH(10) // Debouncing module counter width (2^COUNTER_WIDTH * 1/(CLOCK_RATE))*seconds
    ) i_rx_serial_db (
        .clk        (clk),        // Clock signal
        .reset_n    (rst_n),      // Asynchronous active low reset
        .signal_in  (rx_serial),  // Signal to be debounced
        .signal_out (rx_serial_db)// Debounced signal output
    );

    assign rx_serial_filtered = db_rx_serial ? rx_serial_db : rx_serial;

    baud_rate_generator #(
      .CLOCK_RATE(CLOCK_RATE),      // System clock frequency in Hz
      .BAUD_RATE(BAUD_RATE),        // Desired baud rate in bps
      .OVERSAMPLE(16),              // 16x oversampling baud clock: each baud clocks are 50% duty cycle clocks 
      .INITIAL_POLARITY(1'b0)
    )i_baud_clk_gen(
        .clk(clk),                          // System clock input
        .rst_n(rst_n),                      // Active-low asynchronous reset
        .baud_clk(baud_clk),                // 16x Baud rate clock output (for UART Rx)
        .restart_baud_clk(restart_baud_clk) // Restart baud clock
    );

    // Synchronize baud_clk to clk domain for edge detection
    reg baud_clk_reg;                // Previous baud_clk value for edge detection
    reg rx_serial_filtered_reg;      // Previous rx_serial_filtered value for edge detection
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_clk_reg <= 0;
            rx_serial_filtered_reg <= 0;
        end else begin
            baud_clk_reg <= baud_clk;
            rx_serial_filtered_reg <= rx_serial_filtered;
        end
    end

    wire baud_clk_rising = ~baud_clk_reg & baud_clk;        // Detect baud clock rising edge
    wire start_bit_detected = rx_serial_filtered_reg & ~rx_serial_filtered;  // Detect falling edge

    // FSM controlling data reception
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= IDLE;
            bit_index          <= 0;
            shift_reg          <= 0;
            calculated_parity  <= 0;
            rx_ready           <= 0;
            frame_error        <= 0;
            parity_error       <= 0;
            rx_index_counter   <= 0;
            data_out           <= 0;
            parity_bit_sampled <= 0;
            sample_counter     <= 0;
        end else begin
            rx_ready <= 0; // Default, will be set to 1 for one cycle when data is ready
            restart_baud_clk <= 0;
            case (state)
                IDLE: begin
                    frame_error        <= 0;
                    parity_error       <= 0;
                    rx_index_counter   <= 0;
                    bit_index          <= 0;
                    calculated_parity  <= 0;
                    shift_reg          <= 0;
                    parity_bit_sampled <= 0;
                    sample_counter     <= 0;
                    if (start_bit_detected) begin  // Start bit detected (low)
                        state          <= START_BIT;
                        restart_baud_clk <= 1;
                    end
                end
                START_BIT: begin
                    if(baud_clk_rising) begin
                        sample_counter <= sample_counter + rx_serial_filtered;
                        if (rx_index_counter <= 8 && sample_counter >= 4) begin
                            // already too many ones, impossible to be start bit: go back to IDLE for early exit
                            state <= IDLE;
                        end
                        if (rx_index_counter == 4'b1111) begin // After 16 baud cycles
                            if (sample_counter <= 8) begin // Valid start bit detected
                                state <= DATA_BITS;
                            end else begin // Noise or invalid start bit
                                state <= IDLE;
                            end
                            rx_index_counter <= 0;
                            sample_counter <= 0;
                        end else begin
                            rx_index_counter <= rx_index_counter + 1;
                        end
                    end
                end
                DATA_BITS: begin
                    if(baud_clk_rising) begin
                        sample_counter <= sample_counter + rx_serial_filtered;
                        if (rx_index_counter == 4'b1111) begin // After 16 samples
                            if (sample_counter > 8) begin // Majority of samples are 1
                                shift_reg[bit_index] <= 1;
                                calculated_parity <= calculated_parity ^ 1;
                            end else begin // Majority of samples are 0
                                shift_reg[bit_index] <= 0; 
                                calculated_parity <= calculated_parity ^ 0;
                            end
                            sample_counter     <= 0;
                            rx_index_counter   <= 0;
                            bit_index          <= bit_index + 1;

                            if (bit_index == 7) begin // All data bits received
                                if (parity_en) begin
                                    state <= PARITY_BIT;
                                end else begin
                                    state <= STOP_BIT;
                                    bit_index <= 0;
                                end
                            end
                        end else begin
                            rx_index_counter <= rx_index_counter + 1;
                        end
                    end
                end

                PARITY_BIT: begin
                    if(baud_clk_rising) begin
                        sample_counter <= sample_counter + rx_serial_filtered;
                        if (rx_index_counter == 4'b1111) begin // After 16 samples
                            parity_bit_sampled <= (sample_counter > 8) ? 1 : 0;
                            sample_counter     <= 0;
                            rx_index_counter   <= 0;

                            if ((parity_mode == 0 && (calculated_parity != parity_bit_sampled)) ||
                                (parity_mode == 1 && (calculated_parity == parity_bit_sampled))) begin
                                parity_error <= 1;
                            end

                            state <= STOP_BIT;
                        end else begin
                            rx_index_counter <= rx_index_counter + 1;
                        end
                    end
                end

                STOP_BIT: begin
                    if(baud_clk_rising) begin
                        sample_counter <= sample_counter + rx_serial_filtered;
                        // Check for early detection of the next start bit
                        if (start_bit_detected) begin
                            // Early start bit detected, process the current data and go to start bit state
                            if (sample_counter <= (rx_index_counter >> 1)) frame_error <= 1; // Majority of stop bit samples are not '1'
                            rx_ready <= 1;
                            data_out <= shift_reg;
                            // Prepare for next frame
                            state <= START_BIT;
                            restart_baud_clk <= 1;
                            sample_counter <= 0;
                            rx_index_counter <= 0;
                        end else if (rx_index_counter == 4'b1111) begin // After 16 samples
                            if (sample_counter <= 8) frame_error <= 1; // Stop bit should be '1'
                            rx_ready <= 1;
                            data_out <= shift_reg;
                            state <= IDLE;
                            sample_counter <= 0;
                            rx_index_counter <= 0;
                        end else begin
                            rx_index_counter <= rx_index_counter + 1;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
