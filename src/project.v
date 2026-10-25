/*
 * Programmable protocol engine for Tiny Tapeout.
 * SPDX-License-Identifier: Apache-2.0
 *
 * ui_in[0]  host SCK     uo_out[0]  host MISO
 * ui_in[1]  host CS_N    uo_out[1]  IRQ
 * ui_in[2]  host MOSI    uo_out[2]  RX FIFO has data
 *                        uo_out[3]  TX FIFO has space
 * uio[7:0]  engine pins 0..7 (input, push-pull or open-drain, per pin)
 *
 * STARTER SKELETON (Phase 2): the wiring is done. Fill in the TODO(P2) parts:
 * the register writes, the register read-back, and the pin unit.
 */
`default_nettype none

module tt_um_amaysonline_protoemu (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    // ---- input synchronisers (two flip-flops on every asynchronous input) ----
    reg [7:0] pin_s1, pin_s2;
    reg [2:0] host_s1, host_s2;
    always @(posedge clk) begin
        pin_s1  <= uio_in;
        pin_s2  <= pin_s1;
        host_s1 <= ui_in[2:0];
        host_s2 <= host_s1;
    end

    // ---- host interface ---------------------------------------------------------
    wire       wr_en, rd_en, miso;
    wire [6:0] addr;
    wire [7:0] wdata;
    reg  [7:0] rdata;

    pe_host u_host (
        .clk(clk), .rst_n(rst_n),
        .sck(host_s2[0]), .csn(host_s2[1]), .mosi(host_s2[2]), .miso(miso),
        .wr_en(wr_en), .addr(addr), .wdata(wdata), .rd_en(rd_en), .rdata(rdata)
    );

    // ---- registers ------------------------------------------------------------
    reg        ctrl_en;
    reg [15:0] clkdiv;
    reg [15:0] pinmode;          // 2 bits per pin: 00 input, 01 push-pull, 10 open-drain
    reg [2:0]  out_base, in_base, set_base, set_count, side_pin, jmp_pin;
    reg        out_msb, in_msb;
    reg [7:0]  watch_mask;
    reg        rx_ovf;
    reg [15:0] imem [0:31];

    wire wr_ctrl  = wr_en && addr == 7'h00;
    wire restart  = wr_ctrl && wdata[1];
    wire fifo_clr = wr_ctrl && wdata[2];
    wire irq_clr  = wr_en && addr == 7'h0C;

    always @(posedge clk) begin
        if (!rst_n) begin
            ctrl_en <= 1'b0;   clkdiv <= 16'd0;  pinmode <= 16'd0;
            out_base <= 3'd0;  in_base <= 3'd0;  set_base <= 3'd0;  set_count <= 3'd1;
            side_pin <= 3'd0;  jmp_pin <= 3'd0;  out_msb <= 1'b0;   in_msb <= 1'b0;
            watch_mask <= 8'hFF;
        end else if (wr_en) begin
            case (addr)
                7'h00: ctrl_en <= wdata[0];
                7'h02: clkdiv[7:0]  <= wdata;
                7'h03: clkdiv[15:8] <= wdata;
                // TODO(P2): 0x04/0x05 pinmode low/high byte, 0x06 out_base[2:0] + in_base[5:3],
                //           0x07 set_base + set_count, 0x08 side_pin + jmp_pin,
                //           0x09 out_msb[0] + in_msb[1], 0x10 watch_mask
                default: ;
            endcase
        end
    end

    // instruction memory: byte-addressed at 0x40-0x7F, high byte first; no reset needed
    always @(posedge clk) begin
        if (wr_en && addr[6]) begin
            if (addr[0]) imem[addr[5:1]][7:0]  <= wdata;
            else         imem[addr[5:1]][15:8] <= wdata;
        end
    end

    // ---- clock divider: one engine tick every clkdiv+1 clocks --------------------
    reg [15:0] divcnt;
    wire tick = ctrl_en && (divcnt >= clkdiv);
    always @(posedge clk) begin
        if (!rst_n || !ctrl_en || tick) divcnt <= 16'd0;
        else                            divcnt <= divcnt + 16'd1;
    end

    // ---- FIFOs ----------------------------------------------------------------
    wire       tx_empty, tx_full, rx_empty, rx_full;
    wire [7:0] tx_dout, rx_dout, rx_din;
    wire       tx_pop, rx_push, rx_drop;

    pe_fifo u_txf (
        .clk(clk), .rst_n(rst_n), .clr(fifo_clr),
        .push(wr_en && addr == 7'h0A), .din(wdata),
        .pop(tx_pop), .dout(tx_dout), .empty(tx_empty), .full(tx_full)
    );
    pe_fifo u_rxf (
        .clk(clk), .rst_n(rst_n), .clr(fifo_clr),
        .push(rx_push), .din(rx_din),
        .pop(rd_en && addr == 7'h0B), .dout(rx_dout), .empty(rx_empty), .full(rx_full)
    );

    always @(posedge clk) begin
        if (!rst_n || fifo_clr) rx_ovf <= 1'b0;
        else if (rx_drop)       rx_ovf <= 1'b1;
    end

    // ---- engine core ------------------------------------------------------------
    wire [4:0] pc;
    wire [7:0] out_val, x, y;
    wire       irq, stalled;

    pe_core u_core (
        .clk(clk), .rst_n(rst_n), .en(ctrl_en), .restart(restart), .tick(tick),
        .pc_o(pc), .instr(imem[pc]),
        .pins_in(pin_s2), .out_val(out_val),
        .out_base(out_base), .in_base(in_base), .set_base(set_base), .set_count(set_count),
        .side_pin(side_pin), .jmp_pin(jmp_pin), .out_msb(out_msb), .in_msb(in_msb),
        .watch_mask(watch_mask),
        .tx_empty(tx_empty), .tx_data(tx_dout), .tx_pop(tx_pop),
        .rx_full(rx_full), .rx_data(rx_din), .rx_push(rx_push), .rx_drop(rx_drop),
        .irq(irq), .irq_clr(irq_clr), .stalled(stalled), .x_o(x), .y_o(y)
    );

    // ---- register read-back -----------------------------------------------------
    wire [7:0] status = {1'b0, stalled, rx_ovf, irq, rx_full, rx_empty, tx_full, tx_empty};
    always @(*) begin
        if (addr[6]) begin
            rdata = addr[0] ? imem[addr[5:1]][7:0] : imem[addr[5:1]][15:8];
        end else begin
            case (addr[5:0])
                6'h00: rdata = {7'd0, ctrl_en};
                6'h01: rdata = status;
                6'h02: rdata = clkdiv[7:0];
                // TODO(P2): read back every register you can write (same bit positions), plus
                //           0x0B RX FIFO head (rx_dout), 0x0D pc, 0x0E x, 0x0F y
                default: rdata = 8'h00;
            endcase
        end
    end

    // ---- pads ---------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : g_pin
            wire [1:0] mode = pinmode[2*i +: 2];
            // TODO(P2): 01 push-pull: drive out_val[i].   10 open-drain: drive 0 when out_val[i]
            //           is 0, let go (uio_oe = 0) when it is 1.   00 / 11: input, never drive.
            assign uio_out[i] = 1'b0;
            assign uio_oe[i]  = 1'b0;
        end
    endgenerate

    assign uo_out = {4'b0, ~tx_full, ~rx_empty, irq, miso};

    wire _unused = &{ena, ui_in[7:3], 1'b0};
endmodule
