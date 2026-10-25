`default_nettype none
`timescale 1ns / 1ps
//======================================================================
// baud_gen.v
//
// Baud rate generator for the UART.  Produces a single-cycle "tick"
// pulse at OVERSAMPLE x BAUD_RATE.  The receiver uses every tick to
// oversample the line; the transmitter counts 16 ticks per bit time.
//
// Sharing one generator between TX and RX keeps them on the same time
// base and costs only one counter.
//
// Target: Xilinx Spartan-7 XC7S50 (Real Digital Boolean board), 100 MHz.
//======================================================================
module baud_gen #(
    parameter integer CLK_FREQ   = 100_000_000,  // input clock in Hz
    parameter integer BAUD_RATE  = 115_200,      // desired baud rate
    parameter integer OVERSAMPLE = 16            // ticks per bit period
) (
    input  wire clk,    // system clock
    input  wire rst,    // synchronous, active-high reset
    output reg  tick    // 1-clock pulse at OVERSAMPLE*BAUD_RATE
);

    // Clock cycles between ticks, rounded to nearest.
    //   100_000_000 / (115200 * 16) = 54.25  ->  DIVISOR = 54
    // Actual tick rate = 100e6/54 = 1.8519 MHz  ->  115740.7 baud,
    // i.e. +0.47% error.  UARTs tolerate roughly +/-2-3% per frame, so
    // this is comfortably inside spec.
    localparam integer TICK_RATE = BAUD_RATE * OVERSAMPLE;
    localparam integer DIVISOR   = (CLK_FREQ + TICK_RATE/2) / TICK_RATE;
    localparam integer CNT_W     = (DIVISOR <= 1) ? 1 : $clog2(DIVISOR);

    reg [CNT_W-1:0] cnt;

    always @(posedge clk) begin
        if (rst) begin
            cnt  <= {CNT_W{1'b0}};
            tick <= 1'b0;
        end else if (cnt == DIVISOR-1) begin
            cnt  <= {CNT_W{1'b0}};
            tick <= 1'b1;                 // one-cycle pulse
        end else begin
            cnt  <= cnt + 1'b1;
            tick <= 1'b0;
        end
    end

endmodule
