module top_uart_test (
    input wire rx_serial_in,    // Connected to the PMOD pin for RX
    output wire tx_serial_out   // Connected to the PMOD pin for TX
);
    wire       clk;
    wire       rst_n;
    
    reg        tx_start;
    reg [7:0]  tx_data_in;
    reg        tx_data_valid;

    wire [7:0] rx_data_out;
    wire       rx_ready;
    wire       tx_busy;
    wire       parity_error;
    
    // New signals for UART control features
    wire       parity_en;       // Enable parity bit
    wire       parity_mode;     // Parity mode: 0 = even, 1 = odd
    wire       stop_bits;       // Number of stop bits: 0 = 1 stop bit, 1 = 2 stop bits
    wire       break_signal;    // Signal to send a break condition
    
    // Default settings for UART configuration (can be changed as needed)
    assign parity_en = 1'b0;      // Disable parity for simple echo test
    assign parity_mode = 1'b0;    // Default to even parity (not used in this case)
    assign stop_bits = 1'b0;      // Default to 1 stop bit
    assign break_signal = 1'b0;   // No break condition
    
    // Instantiate system-level clock and reset module (assumed to be provided)
    design_1 i_design_1(
        .peripheral_aresetn(rst_n),
        .pl_clk0(clk)
    );
    
    // Instantiate the uart_interface module with updated inputs
    uart_interface #(
        .CLOCK_RATE(200_000_000),  // System clock frequency (adjust if different)
        .BAUD_RATE(9600)           // Baud rate
    ) i_uart_inst (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data_in(tx_data_in),
        .rx_serial_in(rx_serial_in),
        .tx_serial_out(tx_serial_out),
        .rx_data_out(rx_data_out),
        .rx_ready(rx_ready),
        .parity_error(parity_error),
        .tx_busy(tx_busy),
        .parity_en(parity_en),        // Connect parity enable signal
        .parity_mode(parity_mode),    // Connect parity mode signal
        .stop_bits(stop_bits),        // Connect stop bits signal
        .break_signal(break_signal)   // Connect break signal
    );
    
    // Echo received data back to transmitter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_start      <= 1'b0;
            tx_data_in    <= 8'b0;
            tx_data_valid <= 1'b0;
        end else begin
            if (rx_ready) begin
                tx_data_in    <= rx_data_out;  // Echo received data
                tx_data_valid <= 1'b1;
            end

            if (tx_data_valid && !tx_busy) begin
                tx_start      <= 1'b1;  // Trigger transmission
                tx_data_valid <= 1'b0;
            end else begin
                tx_start <= 1'b0;       // Deassert after one clock cycle
            end
        end
    end
    
    // Instantiate ILA core for signal analysis (unchanged)
    ila_0 ila_inst (
        .clk(clk), // Connect to system clock
        .probe0(tx_start),        // 1-bit
        .probe1(tx_data_in),      // 8-bit
        .probe2(tx_serial_out),   // 1-bit
        .probe3(rx_serial_in),    // 1-bit
        .probe4(rx_data_out),     // 8-bit
        .probe5(rx_ready),        // 1-bit
        .probe6(parity_error),    // 1-bit
        .probe7(tx_busy),         // 1-bit
        .probe8(i_uart_inst.i_uart_tx.fsm_state),     // 2-bit
        .probe9(i_uart_inst.i_uart_tx.bit_index),     // 3-bit
        .probe10(i_uart_inst.i_uart_rx.fsm_state),    // 2-bit
        .probe11(i_uart_inst.i_uart_rx.bit_index)     // 3-bit
    );
    
endmodule
