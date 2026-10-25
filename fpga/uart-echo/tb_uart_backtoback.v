`timescale 1ns / 1ps
module tb_b2b;
    parameter integer BIT_PERIOD = 8681;     // ns per bit at the SENDER
    reg clk = 0, rst = 1, rx = 1;
    wire tick;
    wire [7:0] rx_data; wire rx_done, frame_err;
    always #5 clk = ~clk;                    // 100 MHz, like the Boolean board
    baud_gen #(.CLK_FREQ(100_000_000), .BAUD_RATE(115_200), .OVERSAMPLE(16)) bg (.clk(clk), .rst(rst), .tick(tick));
    uart_rx #(.OVERSAMPLE(16)) ur (.clk(clk), .rst(rst), .tick(tick), .rx(rx), .rx_data(rx_data), .rx_done(rx_done), .frame_err(frame_err));
    integer got = 0, bad = 0, i, k;
    reg [7:0] exp [0:9];
    always @(posedge clk) if (rx_done) begin
        if (rx_data !== exp[got] || frame_err) bad = bad + 1;
        got = got + 1;
    end
    initial begin
        for (k = 0; k < 10; k = k + 1) exp[k] = 8'h30 + k * 7;
        repeat (10) @(posedge clk); rst = 0; #20000;
        for (k = 0; k < 10; k = k + 1) begin          // ten frames, NO gap between them
            rx = 0; #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin rx = exp[k][i]; #(BIT_PERIOD); end
            rx = 1; #(BIT_PERIOD);
        end
        #50000;
        $display("sender bit period %0d ns: received %0d of 10, %0d wrong", BIT_PERIOD, got, bad);
        $finish;
    end
endmodule
