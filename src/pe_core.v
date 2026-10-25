`default_nettype none
// Protocol engine core: one 16-bit instruction per tick.
// [15:13] opcode  [12] side-set enable  [11] side-set value  [10:8] delay  [7:0] argument
//
// STARTER SKELETON. Search for TODO(P1) in Phase 1 and TODO(P2) in Phase 2.
// The ports, decode, helpers and the OUT instruction are done for you; OUT is the
// worked example to copy from.
module pe_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        restart,
    input  wire        tick,
    // program memory
    output wire [4:0]  pc_o,
    input  wire [15:0] instr,
    // pins
    input  wire [7:0]  pins_in,      // already synchronised
    output reg  [7:0]  out_val,
    // configuration
    input  wire [2:0]  out_base,
    input  wire [2:0]  in_base,
    input  wire [2:0]  set_base,
    input  wire [2:0]  set_count,
    input  wire [2:0]  side_pin,
    input  wire [2:0]  jmp_pin,
    input  wire        out_msb,
    input  wire        in_msb,
    input  wire [7:0]  watch_mask,
    // TX FIFO (host -> engine)
    input  wire        tx_empty,
    input  wire [7:0]  tx_data,
    output wire        tx_pop,
    // RX FIFO (engine -> host)
    input  wire        rx_full,
    output wire [7:0]  rx_data,
    output wire        rx_push,
    output wire        rx_drop,
    // status
    output reg         irq,
    input  wire        irq_clr,
    output wire        stalled,
    output wire [7:0]  x_o,
    output wire [7:0]  y_o
);
    localparam OP_JMP = 3'd0, OP_WAIT = 3'd1, OP_IN = 3'd2, OP_OUT = 3'd3,
               OP_PP  = 3'd4, OP_MOV  = 3'd5, OP_SET = 3'd6, OP_IRQ = 3'd7;

    reg [4:0] pc;
    reg [2:0] dly;
    reg [7:0] x, y, isr, osr, snap, timer;
    reg [3:0] icnt, ocnt;          // bits shifted in / out so far (0..8). ocnt = 8 means OSR empty

    assign pc_o = pc;
    assign x_o  = x;
    assign y_o  = y;

    // ---- decode (done) --------------------------------------------------------
    wire [2:0] opc   = instr[15:13];
    wire       sse   = instr[12];
    wire       ssv   = instr[11];
    wire [2:0] delay = instr[10:8];
    wire [7:0] arg   = instr[7:0];
    wire [3:0] n     = (arg[2:0] == 3'd0) ? 4'd8 : {1'b0, arg[2:0]};  // IN/OUT bit count

    // ---- helpers (done) -------------------------------------------------------
    function [7:0] rotl(input [7:0] v, input [2:0] b);       // rotate left by b
        reg [15:0] t;
        begin t = {v, v} << b; rotl = t[15:8]; end
    endfunction
    function [7:0] rotr(input [7:0] v, input [2:0] b);       // rotate right by b
        reg [15:0] t;
        begin t = {v, v} >> b; rotr = t[7:0]; end
    endfunction
    function [7:0] lowmask(input [3:0] k);                    // k ones: lowmask(3) = 8'b0000_0111
        begin lowmask = (9'd1 << k) - 9'd1; end
    endfunction
    function [7:0] rev8(input [7:0] v);                       // bit reverse
        integer i;
        begin for (i = 0; i < 8; i = i + 1) rev8[i] = v[7 - i]; end
    endfunction

    wire [7:0] in_val = rotr(pins_in, in_base);               // pins, starting at in_base

    // ---- stall conditions -----------------------------------------------------
    wire is_pull = arg[7];
    wire noblock = arg[6];
    // TODO(P2): WAIT stalls until pins_in[arg[2:0]] == arg[7]. With arg[6] set (WAIT CHANGE)
    //           it stalls until ((pins_in ^ snap) & watch_mask) != 0.
    //           A PULL without noblock stalls while tx_empty; a PUSH without noblock while rx_full.
    wire stall = 1'b0;

    wire exec = en && tick && (dly == 3'd0);    // this tick works on the current instruction
    wire done = exec && !stall;                 // ... and finishes it
    assign stalled = en && (dly == 3'd0) && stall;

    // ---- JMP condition ----------------------------------------------------------
    reg take;
    always @(*) begin
        case (arg[7:5])
            3'd0: take = 1'b1;                  // unconditional (Phase 1 needs only this)
            // TODO(P2): 1: X == 0   2: X != 0 (X--)   3: Y == 0   4: Y != 0 (Y--)
            //           5: X != Y   6: pins_in[jmp_pin]   7: OSR not empty (ocnt != 8)
            default: take = 1'b0;
        endcase
    end

    // ---- OUT data path (done: the worked example) -------------------------------
    // MSB first takes the top n bits and shifts left; LSB first takes the bottom n and shifts right.
    wire [7:0] out_bits    = out_msb ? ((osr >> (4'd8 - n)) & lowmask(n)) : (osr & lowmask(n));
    wire [7:0] osr_shifted = out_msb ? (osr << n) : (osr >> n);

    // ---- IN data path -----------------------------------------------------------
    // TODO(P2): pick the source (arg[7:5]: 0 in_val, 1 x, 2 y, 3 zeros), keep its low n bits,
    //           and shift them into the ISR. in_msb = 1: shift left, new bits enter at the bottom.
    //           in_msb = 0: shift right, new bits enter at the top (so LSB-first data lines up).
    wire [7:0] isr_shifted = isr;

    // ---- MOV source -------------------------------------------------------------
    // TODO(P2): source arg[2:0]: 0 in_val, 1 x, 2 y, 3 isr, 4 osr, 5 zero, 6 timer.
    //           operation arg[4:3]: 0 none, 1 invert, 2 bit-reverse (use rev8).
    wire [7:0] mov_val = 8'd0;

    // ---- pin writes from OUT / SET / MOV --------------------------------------
    // pmask says which pins this instruction writes, pdata what it writes to them.
    reg [7:0] pmask, pdata;
    always @(*) begin
        pmask = 8'd0;
        pdata = 8'd0;
        if (opc == OP_OUT && arg[7:5] == 3'd0) begin            // done: OUT PINS
            pmask = rotl(lowmask(n), out_base);
            pdata = rotl(out_bits, out_base);
        end else if (opc == OP_SET && arg[7:5] == 3'd0) begin
            // TODO(P1): SET PINS writes the low set_count bits of arg[4:0] to the pins starting
            //           at set_base. Treat set_count above 5 as 5. Same shape as OUT PINS above.
        end else if (opc == OP_MOV && arg[7:5] == 3'd0) begin
            // TODO(P2): MOV PINS writes all 8 bits of mov_val, rotated by out_base.
        end
    end

    wire [7:0] ov_after = done ? ((out_val & ~pmask) | (pdata & pmask)) : out_val;
    wire [7:0] ss_bit   = 8'd1 << side_pin;

    // ---- FIFO handshakes ----------------------------------------------------------
    // TODO(P2): tx_pop when a PULL completes with data available; rx_push when a PUSH completes
    //           with space; rx_drop when a noblock PUSH finds the FIFO full.
    assign tx_pop  = 1'b0;
    assign rx_push = 1'b0;
    assign rx_drop = 1'b0;
    assign rx_data = isr;

    // ---- pins and IRQ -----------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            out_val <= 8'hFF;   // every line idles high: UART idle, CS inactive, I2C released
            irq     <= 1'b0;
        end else begin
            // TODO(P1): on `exec`, out_val takes ov_after, and then, if sse, bit side_pin is
            //           forced to ssv. Side-set must apply even while the instruction stalls.
            // TODO(P2): a completed IRQ instruction sets irq to arg[7]; irq_clr clears it.
        end
    end

    // ---- everything else ----------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n || restart) begin
            pc <= 5'd0;  dly <= 3'd0;
            x <= 8'd0;   y <= 8'd0;
            isr <= 8'd0; icnt <= 4'd0;
            osr <= 8'd0; ocnt <= 4'd8;
            snap <= 8'd0; timer <= 8'd0;
        end else if (en && tick) begin
            // TODO(P2): timer counts up every tick and sticks at 255.
            if (dly != 3'd0) begin
                // TODO(P1): count the delay down by one.
            end else if (!stall) begin
                // TODO(P1): move to the next instruction (pc + 1) and load dly from the delay field.
                case (opc)
                    OP_JMP: begin
                        // TODO(P1): if take, jump to arg[4:0] (a later <= in this block wins).
                        // TODO(P2): X-- (cond 2) and Y-- (cond 4) decrement whether or not they jump.
                    end
                    OP_OUT: begin                                   // done: the worked example
                        osr  <= osr_shifted;
                        ocnt <= ({1'b0, ocnt} + {1'b0, n} > 5'd8) ? 4'd8 : ocnt + n;
                        if (arg[7:5] == 3'd1) x <= out_bits;
                        if (arg[7:5] == 3'd2) y <= out_bits;
                    end
                    // TODO(P2): OP_WAIT  WAIT CHANGE (arg[6]) stores pins_in into snap when it completes
                    // TODO(P2): OP_IN    isr <= isr_shifted, icnt grows by n (stop at 8)
                    // TODO(P2): OP_PP    PULL: osr <= tx_data (or x if the FIFO is empty), ocnt <= 0
                    //                    PUSH: isr <= 0, icnt <= 0
                    // TODO(P2): OP_MOV   destinations arg[7:5]: 1 x, 2 y, 3 isr (icnt <= 0),
                    //                    4 osr (ocnt <= 0). Reading the timer (source 6) sets it to 1.
                    // TODO(P2): OP_SET   destination 1 = X, 2 = Y (value arg[4:0])
                    default: ;
                endcase
            end
        end
    end

`ifdef FORMAL
    // ---- formal properties (formal/core.sby). These describe the finished core. --------
    reg f_past = 1'b0;
    always @(posedge clk) f_past <= 1'b1;
    always @(*) if (!f_past) assume (!rst_n);

    always @(posedge clk) if (f_past && $past(rst_n) && rst_n && !$past(restart)) begin
        if ($past(en && tick && dly != 3'd0)) begin           // during a delay nothing moves
            assert (out_val == $past(out_val));
            assert (pc == $past(pc));
            assert (dly == $past(dly) - 3'd1);
        end
        if ($past(exec && sse))                               // side-set always wins on its pin
            assert (out_val[$past(side_pin)] == $past(ssv));
        if ($past(exec && stall))                             // a stalled instruction does not advance
            assert (pc == $past(pc) && dly == 3'd0);
        if (!$past(en && tick)) begin                         // the engine only acts on ticks
            assert (out_val == $past(out_val));
            assert (pc == $past(pc));
        end
    end
    always @(*) if (f_past && rst_n) assert (icnt <= 4'd8 && ocnt <= 4'd8);
`endif
endmodule
