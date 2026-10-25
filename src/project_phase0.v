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
    wire rst = ~rst_n;              // our modules use active-high reset
    wire tick, tx, tx_busy, tx_done;

    baud_gen #(.CLK_FREQ(50_000_000), .BAUD_RATE(115_200), .OVERSAMPLE(16)) u_baud (
        .clk(clk), .rst(rst), .tick(tick)
    );

    uart_tx #(.OVERSAMPLE(16)) u_tx (
        .clk(clk), .rst(rst), .tick(tick),
        .tx_start(~tx_busy),        // send ui_in over and over
        .tx_data(ui_in),
        .tx(tx), .tx_busy(tx_busy), .tx_done(tx_done)
    );

    assign uo_out  = {7'b0, tx};
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;
    wire _unused = &{ena, uio_in, tx_done, 1'b0};
endmodule
