`default_nettype none
`timescale 1ns / 1ps
//======================================================================
// uart_rx.v
//
// UART receiver, 8N1, with 16x oversampling and a 3-sample majority
// vote taken at the centre of every bit.
//
// The incoming line is asynchronous to clk, so it first passes through
// a two-flop synchroniser.  A falling edge on the synchronised line
// starts the frame; from there the tick counter (0..15) tracks position
// inside each bit period:
//
//   tick_cnt:  0 . . . 6  7  8  9  10 . . . 15
//                        ^  ^  ^
//                        majority samples (bit centre)
//
// Voting over three adjacent samples rejects a single glitch or a
// narrow noise pulse landing exactly on the sample point.
//======================================================================
module uart_rx #(
    parameter integer OVERSAMPLE = 16   // ticks per bit (must match baud_gen)
) (
    input  wire       clk,        // system clock
    input  wire       rst,        // synchronous, active-high reset
    input  wire       tick,       // 16x baud tick from baud_gen
    input  wire       rx,         // serial input (asynchronous)
    output reg  [7:0] rx_data,    // last byte received
    output reg        rx_done,    // 1-clock pulse when rx_data is valid
    output reg        frame_err   // stop bit was not high (sticky per frame)
);

    //------------------------------------------------------------------
    // Input synchroniser + falling-edge detect
    //------------------------------------------------------------------
    reg [1:0] rx_sync;
    reg       rx_prev;

    always @(posedge clk) begin
        if (rst) begin
            rx_sync <= 2'b11;    // line idles high
            rx_prev <= 1'b1;
        end else begin
            rx_sync <= {rx_sync[0], rx};
            rx_prev <= rx_sync[1];
        end
    end

    wire rx_s     = rx_sync[1];              // metastability-safe line value
    wire start_fe = rx_prev & ~rx_s;         // 1->0 transition = start bit

    //------------------------------------------------------------------
    // FSM
    //------------------------------------------------------------------
    // S_IDLE  : watch for a falling edge.  The edge resets tick_cnt, so
    //           the counter is phase-aligned to the start of the frame.
    // S_START : sample the start bit at its centre.  If the majority is
    //           1 the edge was noise -> abort back to S_IDLE.  Otherwise
    //           run out the full bit so bit 0's centre lands on ticks
    //           7/8/9 of the next state.
    // S_DATA  : 8 bits, LSB first.  Shift the majority result into the
    //           top of data_sr; after 8 shifts the byte is right-aligned.
    // S_STOP  : sample the stop bit.  A 0 here means the framing is
    //           wrong (baud mismatch or a break) -> frame_err.  rx_data
    //           and rx_done are presented at the end of the stop bit,
    //           which also guarantees we never mistake the tail of this
    //           frame for the start of the next one.
    //------------------------------------------------------------------
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    localparam integer TICK_W = $clog2(OVERSAMPLE);
    localparam integer MID    = OVERSAMPLE/2;   // 8 for 16x oversampling

    reg [1:0]        state;
    reg [TICK_W-1:0] tick_cnt;   // position within the current bit
    reg [2:0]        bit_idx;    // 0..7 data bit counter
    reg [7:0]        data_sr;    // receive shift register
    reg [1:0]        votes;      // number of 1s seen at the bit centre

    // Sample window: the three ticks straddling the bit centre.
    wire in_window = (tick_cnt == MID-1) || (tick_cnt == MID) || (tick_cnt == MID+1);
    // Majority of three -> at least two 1s.
    wire bit_val   = (votes >= 2'd2);
    // Last tick of the bit period.
    wire bit_end   = tick && (tick_cnt == OVERSAMPLE-1);

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            tick_cnt  <= {TICK_W{1'b0}};
            bit_idx   <= 3'd0;
            data_sr   <= 8'd0;
            votes     <= 2'd0;
            rx_data   <= 8'd0;
            rx_done   <= 1'b0;
            frame_err <= 1'b0;
        end else begin
            rx_done <= 1'b0;                  // default: no pulse this clock

            // Common oversample bookkeeping: count ticks and accumulate
            // the three centre samples.  Individual states only need to
            // look at bit_end and bit_val.
            if (state != S_IDLE && tick) begin
                if (in_window)
                    votes <= votes + rx_s;
                if (tick_cnt == OVERSAMPLE-1)
                    tick_cnt <= {TICK_W{1'b0}};
                else
                    tick_cnt <= tick_cnt + 1'b1;
            end

            case (state)
                //--------------------------------------------------
                S_IDLE: begin
                    tick_cnt <= {TICK_W{1'b0}};
                    bit_idx  <= 3'd0;
                    votes    <= 2'd0;
                    if (start_fe) begin
                        frame_err <= 1'b0;    // fresh frame
                        state     <= S_START;
                    end
                end
                //--------------------------------------------------
                S_START: begin
                    if (bit_end) begin
                        votes <= 2'd0;        // restart the vote for bit 0
                        if (bit_val) begin
                            state <= S_IDLE;  // false start: it was a glitch
                        end else begin
                            bit_idx <= 3'd0;
                            state   <= S_DATA;
                        end
                    end
                end
                //--------------------------------------------------
                S_DATA: begin
                    if (bit_end) begin
                        votes   <= 2'd0;
                        data_sr <= {bit_val, data_sr[7:1]};   // LSB first
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end
                end
                //--------------------------------------------------
                S_STOP: begin
                    if (tick && tick_cnt == MID+2) begin    // votes for the stop bit are in
                        votes     <= 2'd0;
                        frame_err <= ~bit_val;   // stop bit must be high
                        rx_data   <= data_sr;
                        rx_done   <= 1'b1;
                        state     <= S_IDLE;
                    end
                end
                //--------------------------------------------------
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
