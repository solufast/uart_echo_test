`timescale  1 ns / 10 ps

module debounce #(
    parameter COUNTER_WIDTH = 23   // Parameter to specify the number of bits for the counter
)(
    input wire clk,                // Clock signal e.g. clk = 200Mhz
    input wire reset_n,            // Asynchronous active low reset
    input wire signal_in,          // Signal to be debounced
    output reg signal_out          // Debounced signal output
);

    reg [COUNTER_WIDTH-1:0] counter;  // Counter for debounce timing
    reg signal_sync_r;                // Previous state of the input signal

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            signal_out <= 0;          // Reset output signal
            counter <= 0;             // Reset counter
            signal_sync_r <= 0;       // Reset synchronized signal
        end else begin
            if (signal_in != signal_sync_r) begin
                counter <= 0;         // Reset counter if signal changes
                signal_sync_r <= signal_in;  // Update synchronized signal
            end else if (counter == {COUNTER_WIDTH{1'b1}}) begin
                signal_out <= signal_sync_r; // Stable signal, update output
            end else begin
                counter <= counter + 1;      // Increment counter until it reaches max value
            end
        end
    end
endmodule
