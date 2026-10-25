`default_nettype none
// Spartan-7 wrapper: the exact same tt_um_protoemu RTL, with FPGA pins around it.
// Use the Clocking Wizard to make 50 MHz so every clkdiv value matches the chip.
module top_fpga #(
    parameter RESET_ACTIVE_HIGH = 1      // most board push-buttons read 1 when pressed
) (
    input  wire       clk_50,            // 50 MHz from a Clocking Wizard (or your oscillator)
    input  wire       btn_reset,
    // host SPI, e.g. from a Raspberry Pi Pico on a PMOD header
    input  wire       host_sck,
    input  wire       host_csn,
    input  wire       host_mosi,
    output wire       host_miso,
    // status, e.g. to LEDs
    output wire       led_irq,
    output wire       led_rx_ready,
    output wire       led_tx_ready,
    // engine pins 0-7 on a second PMOD header
    inout  wire [7:0] epin
);
    // reset: synchronise the button, release cleanly
    reg [1:0] rst_sync = 2'b00;
    wire pressed = RESET_ACTIVE_HIGH ? btn_reset : ~btn_reset;
    always @(posedge clk_50) rst_sync <= {rst_sync[0], ~pressed};
    wire rst_n = rst_sync[1];

    wire [7:0] uo_out, uio_out, uio_oe;

    tt_um_protoemu dut (
        .ui_in  ({5'b0, host_mosi, host_csn, host_sck}),
        .uo_out (uo_out),
        .uio_in (epin),                   // reads the pad, even while driving it
        .uio_out(uio_out),
        .uio_oe (uio_oe),
        .ena    (1'b1),
        .clk    (clk_50),
        .rst_n  (rst_n)
    );

    // tri-state pads: Vivado turns these into IOBUFs
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : g_pad
            assign epin[i] = uio_oe[i] ? uio_out[i] : 1'bz;
        end
    endgenerate

    assign host_miso    = uo_out[0];
    assign led_irq      = uo_out[1];
    assign led_rx_ready = uo_out[2];
    assign led_tx_ready = uo_out[3];
endmodule
