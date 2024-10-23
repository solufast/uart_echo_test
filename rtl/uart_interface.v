`timescale 1ns / 10ps

module uart_interface #(
    parameter integer CLOCK_RATE = 200_000_000,  // System clock frequency in Hz
    parameter integer BAUD_RATE = 9600           // Desired baud rate in bps
)(
    input  wire       clk,                // System clock
    input  wire       rst_n,              // Active-low asynchronous reset
    input  wire       tx_start,           // Trigger to start data transmission
    input  wire [7:0] tx_data_in,         // Data to be transmitted
    input  wire       rx_serial_in,       // Serial data input for reception
    input  wire       db_rx_serial_in,    // Flag to enable or disable debounce for rx_serial_in: 0:disabled, 1:enabled
    input  wire       parity_en,          // Enable parity bit
    input  wire       parity_mode,        // Parity mode: 0 = even, 1 = odd
    input  wire       stop_bits,          // Number of stop bits: 0 = 1 stop bit, 1 = 2 stop bits
    input  wire       break_signal,       // Signal to send a break condition on TX
    output wire       tx_serial_out,      // Serial data output for transmission
    output wire [7:0] rx_data_out,        // Received data
    output wire       rx_ready,           // Indicates received data is ready
    output wire       parity_error,       // Parity Error
    output wire       tx_busy             // Indicates transmission is in progress
);

    wire rx_baud_clk;
    wire tx_baud_clk;

    // Instantiate the Tx Module 
    uart_tx #(
        .CLOCK_RATE(CLOCK_RATE),
        .BAUD_RATE (BAUD_RATE )
    )i_uart_tx (
        .clk(clk),                         // System clock
        .rst_n(rst_n),                     // Active-low reset
        .tx_start(tx_start),               // Directly connect tx_start (no baud clock needed)
        .tx_data_in(tx_data_in),           // Data to be transmitted
        .parity_en(parity_en),             // Parity enable control
        .parity_mode(parity_mode),         // Parity mode control: even/odd
        .tx_serial(tx_serial_out),         // Serial output (transmitted data)
        .tx_busy(tx_busy)                  // Transmitter busy signal
    );

    // Instantiate the Rx Module (also system clock-based with internal clock divider)
    uart_rx  #(
        .CLOCK_RATE(CLOCK_RATE),
        .BAUD_RATE (BAUD_RATE )
    )i_uart_rx (
        .clk(clk),                         // System clock
        .rst_n(rst_n),                     // Active-low reset
        .rx_serial(rx_serial_in),          // Serial data input
        .db_rx_serial(db_rx_serial_in),    // Flag whether to debounce rx_serial_in or not
        .parity_en(parity_en),             // Parity enable control
        .parity_mode(parity_mode),         // Parity mode control: even/odd
        .data_out(rx_data_out),            // Received data output
        .rx_ready(rx_ready),               // Data ready signal
        .parity_error(parity_error)        // Parity error signal
    );
    
endmodule
