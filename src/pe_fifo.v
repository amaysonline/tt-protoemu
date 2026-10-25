`default_nettype none
// Small synchronous FIFO. push when full and pop when empty are ignored.
// STARTER SKELETON (Phase 2). The formal properties at the bottom will check your work:
//   cd formal && sby -f fifo.sby
module pe_fifo #(
    parameter W = 8,
    parameter AW = 2              // depth = 2**AW
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         clr,      // synchronous clear, like reset
    input  wire         push,
    input  wire [W-1:0] din,
    input  wire         pop,
    output wire [W-1:0] dout,     // oldest entry (0 when empty)
    output wire         empty,
    output wire         full
);
    reg [W-1:0] mem [0:(1<<AW)-1];
    reg [AW-1:0] rp, wp;          // read and write pointers, wrap around naturally
    reg [AW:0]   count;           // one extra bit: count can reach 2**AW

    wire do_push = push && !full;
    wire do_pop  = pop && !empty;

    // TODO(P2): empty, full and dout. Return 0 from dout when the FIFO is empty.
    assign empty = 1'b1;
    assign full  = 1'b0;
    assign dout  = {W{1'b0}};

    always @(posedge clk) begin
        if (!rst_n || clr) begin
            rp <= 0;
            wp <= 0;
            count <= 0;
        end else begin
            // TODO(P2): on do_push store din at mem[wp] and advance wp; on do_pop advance rp;
            //           count goes up, down, or stays the same (both at once = same).
        end
    end

`ifdef FORMAL
    reg f_past = 1'b0;
    always @(posedge clk) f_past <= 1'b1;
    always @(*) if (!f_past) assume (!rst_n);           // start in reset

    always @(*) if (f_past && rst_n) begin
        assert (count <= (1 << AW));                     // never more than DEPTH entries
        assert (wp - rp == count[AW-1:0]);               // pointers agree with count
        assert (empty == (count == 0));
    end
    always @(posedge clk) if (f_past && $past(rst_n) && rst_n && !$past(clr)) begin
        if ($past(push) && $past(full) && !$past(pop))
            assert (count == $past(count));              // push into full is ignored
        if ($past(pop) && $past(empty) && !$past(push))
            assert (count == $past(count));              // pop from empty is ignored
        if ($past(push) && !$past(full) && !$past(pop))
            assert (mem[$past(wp)] == $past(din));       // pushed data is stored
    end
`endif
endmodule
