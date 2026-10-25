`default_nettype none
`timescale 1ns / 1ps
//======================================================================
// uart_tx.v
//
// UART transmitter: 1 start bit, 8 data bits (LSB first), no parity,
// 1 stop bit (8N1).  Driven by the 16x oversample tick from baud_gen;
// each bit lasts exactly 16 ticks.
//
// Handshake:
//   Assert tx_start for one clock while tx_busy is low.  tx_data is
//   captured on that clock.  tx_busy stays high for the whole frame and
//   tx_done pulses for one clock as the stop bit completes.
//======================================================================
module uart_tx #(
    parameter integer OVERSAMPLE = 16   // ticks per bit (must match baud_gen)
) (
    input  wire       clk,        // system clock
    input  wire       rst,        // synchronous, active-high reset
    input  wire       tick,       // 16x baud tick from baud_gen
    input  wire       tx_start,   // 1-clock request to send tx_data
    input  wire [7:0] tx_data,    // byte to transmit
    output reg        tx,         // serial output (idles high)
    output wire       tx_busy,    // high while a frame is in flight
    output reg        tx_done     // 1-clock pulse when the frame is sent
);

    //------------------------------------------------------------------
    // FSM
    //------------------------------------------------------------------
    // S_IDLE  : line held high.  Wait for tx_start, latch the byte.
    // S_START : drive the start bit (low) for 16 ticks.
    // S_DATA  : drive data_reg[bit_idx] for 16 ticks each, LSB first,
    //           advancing bit_idx 0..7.
    // S_STOP  : drive the stop bit (high) for 16 ticks, pulse tx_done,
    //           then return to S_IDLE.
    //
    // Every state leaves only when tick_cnt has counted OVERSAMPLE ticks,
    // so the bit period is identical to the receiver's.
    //------------------------------------------------------------------
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    localparam integer TICK_W = $clog2(OVERSAMPLE);

    reg [1:0]        state;
    reg [TICK_W-1:0] tick_cnt;   // 0..OVERSAMPLE-1 within the current bit
    reg [2:0]        bit_idx;    // which data bit is on the wire
    reg [7:0]        data_reg;   // captured copy of tx_data

    assign tx_busy = (state != S_IDLE);

    // Last tick of the current bit period.
    wire bit_end = tick && (tick_cnt == OVERSAMPLE-1);

    // Combinational picture of what the line should be in each state.
    // Registering it below keeps the output glitch-free on the pad; the
    // extra clock of latency (10 ns) is negligible next to a 8.68 us bit.
    reg tx_next;
    always @* begin
        case (state)
            S_START: tx_next = 1'b0;
            S_DATA:  tx_next = data_reg[bit_idx];
            default: tx_next = 1'b1;      // S_IDLE and S_STOP idle high
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            tick_cnt <= {TICK_W{1'b0}};
            bit_idx  <= 3'd0;
            data_reg <= 8'd0;
            tx       <= 1'b1;
            tx_done  <= 1'b0;
        end else begin
            tx      <= tx_next;
            tx_done <= 1'b0;              // default: no pulse this clock

            case (state)
                //--------------------------------------------------
                S_IDLE: begin
                    tick_cnt <= {TICK_W{1'b0}};
                    bit_idx  <= 3'd0;
                    if (tx_start) begin
                        data_reg <= tx_data;
                        state    <= S_START;
                    end
                end
                //--------------------------------------------------
                S_START: begin
                    if (bit_end) begin
                        tick_cnt <= {TICK_W{1'b0}};
                        bit_idx  <= 3'd0;
                        state    <= S_DATA;
                    end else if (tick) begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
                //--------------------------------------------------
                S_DATA: begin
                    if (bit_end) begin
                        tick_cnt <= {TICK_W{1'b0}};
                        if (bit_idx == 3'd7)
                            state <= S_STOP;      // all 8 bits shipped
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else if (tick) begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
                //--------------------------------------------------
                S_STOP: begin
                    if (bit_end) begin
                        tick_cnt <= {TICK_W{1'b0}};
                        tx_done  <= 1'b1;         // frame complete
                        state    <= S_IDLE;
                    end else if (tick) begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end
                //--------------------------------------------------
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
