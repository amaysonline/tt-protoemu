`timescale 1ns / 1ps
//======================================================================
// tb_uart.v
//
// Self-checking testbench for uart_top, for the Vivado simulator (xsim).
//
// The bench acts as the PC end of the link:
//   - send_byte() bit-bangs a frame into uart_rx_pin at the nominal
//     115200 baud (a period the DUT does NOT share exactly - the DUT
//     runs 0.47% fast - which is the point: it proves the oversampling
//     receiver tolerates the mismatch).
//   - recv_byte() waits for the DUT's echo start bit, then samples
//     uart_tx_pin at each bit centre.
// The two run in a fork/join because the DUT starts echoing before the
// bench has finished driving the stop bit.
//
// Every byte is checked twice: the echoed value and the LED register.
//======================================================================
module tb_uart;

    //------------------------------------------------------------------
    // Parameters
    //------------------------------------------------------------------
    localparam integer CLK_FREQ    = 100_000_000;
    localparam integer BAUD_RATE   = 115_200;
    localparam integer CLK_PERIOD  = 10;      // ns, 100 MHz
    localparam integer BIT_PERIOD  = 8681;    // ns, 1/115200 rounded

    //------------------------------------------------------------------
    // DUT signals
    //------------------------------------------------------------------
    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        rx_line = 1'b1;                // bench -> DUT (idles high)
    wire       tx_line;                       // DUT  -> bench
    wire [7:0] led;

    integer    errors = 0;
    integer    n      = 0;
    reg [7:0]  echoed;

    // Stimulus vectors: alternating patterns, all-zeros and all-ones
    // (the two frames most likely to expose a start/stop bit mistake).
    reg [7:0] vectors [0:5];

    //------------------------------------------------------------------
    // DUT
    //------------------------------------------------------------------
    uart_top #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .uart_rx_pin (rx_line),
        .uart_tx_pin (tx_line),
        .led         (led)
    );

    //------------------------------------------------------------------
    // 100 MHz clock
    //------------------------------------------------------------------
    always #(CLK_PERIOD/2) clk = ~clk;

    //------------------------------------------------------------------
    // Drive one 8N1 frame into the DUT's receiver
    //------------------------------------------------------------------
    task send_byte;
        input [7:0] b;
        integer i;
        begin
            rx_line = 1'b0;                       // start bit
            #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin   // 8 data bits, LSB first
                rx_line = b[i];
                #(BIT_PERIOD);
            end
            rx_line = 1'b1;                       // stop bit
            #(BIT_PERIOD);
        end
    endtask

    //------------------------------------------------------------------
    // Capture one 8N1 frame from the DUT's transmitter
    //------------------------------------------------------------------
    task recv_byte;
        output [7:0] b;
        integer i;
        begin
            @(negedge tx_line);            // start bit edge
            #(BIT_PERIOD*3/2);             // skip start bit, land mid-bit0
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = tx_line;
                #(BIT_PERIOD);
            end
            // Now sitting in the middle of the stop bit.
            if (tx_line !== 1'b1) begin
                $display("[%0t] ERROR: stop bit of echoed frame was not high", $time);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Check one byte end to end
    //------------------------------------------------------------------
    task check_byte;
        input [7:0] b;
        begin
            fork
                send_byte(b);
                recv_byte(echoed);
            join

            if (echoed !== b) begin
                $display("[%0t] ERROR: echo mismatch - sent 0x%02h, echoed 0x%02h",
                         $time, b, echoed);
                errors = errors + 1;
            end else if (led !== b) begin
                $display("[%0t] ERROR: LED mismatch - sent 0x%02h, led = 0x%02h",
                         $time, b, led);
                errors = errors + 1;
            end else begin
                $display("[%0t] PASS : sent 0x%02h, echoed 0x%02h, led = 0x%02h",
                         $time, b, echoed, led);
            end

            #(BIT_PERIOD * 2);             // idle gap between frames
        end
    endtask

    //------------------------------------------------------------------
    // Main stimulus
    //------------------------------------------------------------------
    initial begin
        vectors[0] = 8'h55;
        vectors[1] = 8'hAA;
        vectors[2] = 8'h00;
        vectors[3] = 8'hFF;
        vectors[4] = 8'h3C;
        vectors[5] = 8'h81;

        $display("=== UART loopback testbench: %0d baud, %0d Hz clock ===",
                 BAUD_RATE, CLK_FREQ);

        // Synchronous active-high reset: hold for a few clocks.
        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // Let the line settle before the first frame.
        #(BIT_PERIOD * 2);

        for (n = 0; n < 6; n = n + 1)
            check_byte(vectors[n]);

        if (errors == 0)
            $display("=== TEST PASSED: %0d/%0d bytes matched ===", n, n);
        else
            $display("=== TEST FAILED: %0d error(s) ===", errors);

        $finish;
    end

    //------------------------------------------------------------------
    // Watchdog: a hung FSM must not hang the simulation
    //------------------------------------------------------------------
    initial begin
        #2_000_000;                        // 2 ms, far longer than 6 frames
        $display("=== TEST FAILED: timeout, the DUT stopped responding ===");
        $finish;
    end

endmodule
