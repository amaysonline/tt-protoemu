`default_nettype none
// Host interface: SPI target, mode 0, MSB first. Inputs are already synchronised,
// so SCK must be at most clk/8.
// Transaction: CS low, byte 0 = {write, address[6:0]}, then data bytes. The address
// auto-increments after each data byte, except for the two FIFO registers.
//
// STARTER SKELETON (Phase 2). test_registers in test/test.py checks it.
module pe_host (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sck,
    input  wire       csn,
    input  wire       mosi,
    output wire       miso,
    output reg        wr_en,      // one-cycle pulse: write wdata to addr
    output reg  [6:0] addr,
    output reg  [7:0] wdata,
    output reg        rd_en,      // one-cycle pulse: the byte read from addr has been sent
    input  wire [7:0] rdata       // current value of register 'addr'
);
    localparam A_TXFIFO = 7'h0A, A_RXFIFO = 7'h0B;

    reg       sck_d;
    reg [2:0] bitcnt;
    reg [7:0] sr_in, sr_out;
    reg       phase;      // 0 = command byte, 1 = data bytes
    reg       is_write;
    reg       load;       // load sr_out from rdata on the next falling edge
    reg       inc;        // advance addr next cycle

    wire rise = !csn &&  sck && !sck_d;      // SCK edges, only while selected
    wire fall = !csn && !sck &&  sck_d;
    wire [7:0] byte_in = {sr_in[6:0], mosi}; // the byte including the bit arriving now

    assign miso = sr_out[7];

    always @(posedge clk) begin
        sck_d <= sck;
        wr_en <= 1'b0;
        rd_en <= 1'b0;
        if (!rst_n || csn) begin
            bitcnt <= 3'd0;
            phase  <= 1'b0;
            load   <= 1'b0;
            inc    <= 1'b0;
            if (!rst_n) begin
                addr   <= 7'd0;
                sr_out <= 8'd0;
            end
        end else begin
            // TODO(P2) 1. if inc: clear it and add 1 to addr, unless addr is a FIFO register.
            // TODO(P2) 2. on rise: shift MOSI into sr_in and count the bit.
            //             When bitcnt == 7 a whole byte (byte_in) has arrived:
            //               command byte: phase <= 1, is_write <= byte_in[7], addr <= byte_in[6:0]
            //               data byte:    if writing, pulse wr_en with wdata <= byte_in; set inc
            //             In both cases set load, so the next falling edge fetches rdata.
            //             Also: on the first rising edge of a data byte that is being READ, pulse
            //             rd_en. That is the moment the byte has really started leaving, so popping
            //             the RX FIFO then never loses data if the host stops early.
            // TODO(P2) 3. on fall: if load, sr_out <= rdata and clear load; else shift sr_out left.
        end
    end
endmodule
