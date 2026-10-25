`default_nettype none
`timescale 1ns / 1ps
//======================================================================
// uart_top.v
//
// Top level for the Real Digital Boolean board (Spartan-7 XC7S50).
//
//   - One baud_gen feeds both the transmitter and the receiver.
//   - Every byte received is latched onto the 8 LEDs and echoed back
//     out on uart_tx_pin (a loopback / "does my link work" demo).
//
// Terminal settings: 115200 baud, 8 data bits, no parity, 1 stop bit,
// no flow control.
//======================================================================
module uart_top #(
    parameter integer CLK_FREQ   = 100_000_000,
    parameter integer BAUD_RATE  = 115_200,
    parameter integer OVERSAMPLE = 16
) (
    input  wire       clk,          // 100 MHz board oscillator
    input  wire       rst,          // synchronous, active-high reset (button)
    input  wire       uart_rx_pin,  // serial in  (from USB-UART bridge)
    output wire       uart_tx_pin,  // serial out (to USB-UART bridge)
    output wire [7:0] led           // last byte received
);

    //------------------------------------------------------------------
    // Shared 16x baud tick
    //------------------------------------------------------------------
    wire tick;

    baud_gen #(
        .CLK_FREQ   (CLK_FREQ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (OVERSAMPLE)
    ) u_baud_gen (
        .clk  (clk),
        .rst  (rst),
        .tick (tick)
    );

    //------------------------------------------------------------------
    // Receiver
    //------------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_done;
    wire       frame_err;

    uart_rx #(
        .OVERSAMPLE (OVERSAMPLE)
    ) u_uart_rx (
        .clk       (clk),
        .rst       (rst),
        .tick      (tick),
        .rx        (uart_rx_pin),
        .rx_data   (rx_data),
        .rx_done   (rx_done),
        .frame_err (frame_err)
    );

    //------------------------------------------------------------------
    // Transmitter
    //------------------------------------------------------------------
    reg  [7:0] tx_data;
    reg        tx_start;
    wire       tx_busy;
    wire       tx_done;

    uart_tx #(
        .OVERSAMPLE (OVERSAMPLE)
    ) u_uart_tx (
        .clk      (clk),
        .rst      (rst),
        .tick     (tick),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (uart_tx_pin),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    //------------------------------------------------------------------
    // Echo + LED display
    //------------------------------------------------------------------
    // A clean byte (no framing error) is latched to the LEDs and queued
    // for retransmission.  There is no FIFO: if a byte arrives while the
    // transmitter is still busy it is shown on the LEDs but not echoed.
    // At the same baud rate on both directions that cannot happen for
    // back-to-back frames, only for a host that ignores the echo and
    // streams continuously.
    //------------------------------------------------------------------
    reg [7:0] led_reg;

    always @(posedge clk) begin
        if (rst) begin
            led_reg  <= 8'd0;
            tx_data  <= 8'd0;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;                  // default: single-cycle pulse

            if (rx_done && !frame_err) begin
                led_reg <= rx_data;            // show the byte on the LEDs
                if (!tx_busy) begin
                    tx_data  <= rx_data;
                    tx_start <= 1'b1;          // kick off the echo
                end
            end
        end
    end

    assign led = led_reg;

endmodule
