//==============================================================================
// program_ram.v
// TinyRISC-TinyML -- unified instruction+data RAM for PicoRV32's native
// memory interface.
//
// Timing pattern copied EXACTLY from PicoRV32's own reference memory
// model (picorv32-1.0/testbench_ez.v): mem_ready is REGISTERED (asserted
// the cycle after mem_valid is first observed, i.e. one wait state), not
// combinational -- this is the proven, tested pattern for the module
// holding the entire program, deliberately more conservative than the
// accelerator's 0-wait-state bus (see soc_top.v's header comment for the
// full reasoning).
//
// FIRMWARE_HEX_FILE: path to a $readmemh-compatible hex file (one 32-bit
// word per line, as produced by tools/scripts/makehex.py). Override this
// parameter per instantiation to select firmware_sw.hex vs.
// firmware_hw.hex -- e.g. in tb/integration/soc_top_tb.v:
//   soc_top #(.FIRMWARE_HEX_FILE("firmware_hw.hex")) dut (...);
//
// RAM_WORDS: 8192 words (32 KiB) -- MUST match software/linker/
// sections.lds's RAM LENGTH (0x8000 bytes / 4). If one changes, change
// both.
//==============================================================================
`timescale 1ns / 1ps

module program_ram #(
    parameter FIRMWARE_HEX_FILE = "firmware_sw.hex",
    parameter RAM_WORDS = 8192
)(
    input  wire        clk,
    input  wire         mem_valid,
    input  wire [3:0]   mem_wstrb,
    input  wire [31:0]  mem_addr,
    input  wire [31:0]  mem_wdata,
    output reg          mem_ready,
    output reg  [31:0]  mem_rdata
);

    localparam ADDR_WIDTH = 13; // log2(8192) -- word-address bits, matches RAM_WORDS

    reg [31:0] mem [0:RAM_WORDS-1];

    initial begin
        mem_ready = 1'b0;
        mem_rdata = 32'd0;
        $readmemh(FIRMWARE_HEX_FILE, mem);
    end

    wire [ADDR_WIDTH-1:0] word_addr = mem_addr[ADDR_WIDTH+1:2];

    always @(posedge clk) begin
        mem_ready <= 1'b0;
        if (mem_valid && !mem_ready) begin
            mem_ready <= 1'b1;
            mem_rdata <= mem[word_addr];
            if (mem_wstrb[0]) mem[word_addr][ 7: 0] <= mem_wdata[ 7: 0];
            if (mem_wstrb[1]) mem[word_addr][15: 8] <= mem_wdata[15: 8];
            if (mem_wstrb[2]) mem[word_addr][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) mem[word_addr][31:24] <= mem_wdata[31:24];
        end
    end

endmodule
