`timescale 1ns / 10ps
module baud_rate_generator #(
    parameter integer CLOCK_RATE = 200_000_000,   // System clock frequency in Hz
    parameter integer BAUD_RATE  = 9600,          // Desired baud rate in bps,
    parameter integer OVERSAMPLE = 16,            // Oversampling rate
    parameter INITIAL_POLARITY   = 1'b0           // initial state of baud clock
)(
    input  wire clk,           // System clock input
    input  wire rst_n,         // Active-low asynchronous reset
    output reg  baud_clk,      // Baud rate clock output
    input  wire restart_baud_clk
);

    // Calculate the number of system clock cycles for a 16x baud period
    localparam integer BAUD_PERIOD_COUNTER = CLOCK_RATE / (2 * OVERSAMPLE * BAUD_RATE);

    // Counter to track the number of clock cycles
    reg [31:0] counter = 0;

    // Baud rate clock generation logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter  <= 0;
            baud_clk <= INITIAL_POLARITY;
        end else begin
            if(restart_baud_clk) begin
                counter  <= 0;
                baud_clk <= INITIAL_POLARITY;
            end else begin
                if (counter >= BAUD_PERIOD_COUNTER - 1) begin
                    counter  <= 0;
                    baud_clk <= ~baud_clk;  
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end
endmodule
