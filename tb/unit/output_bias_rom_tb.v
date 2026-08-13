//==============================================================================
// output_bias_rom_tb.v
// Self-checking testbench for generated/hardware/output_bias_rom.v
// HDS Section 3.8 / VIS unit-test matrix. Last of the four ROM testbenches.
//
// Same rationale as the other ROM testbenches: checks addressing/timing
// behavior against the module's own stored content, not hardcoded bias
// values, so it stays valid across retraining. Smallest ROM in the design
// (2 entries, 1-bit address) -- exhaustive coverage is trivial here.
//   T1 - full address sweep (2 entries): dout matches dut.mem[addr]
//   T2 - truly combinational: dout updates with no clock edge
//   T3 - read stability: same address read twice returns the same value
//
// Run:
//   iverilog -o output_bias_rom_tb.vvp output_bias_rom_tb.v \
//       ../../rtl/memory/output_bias_rom.v
//   vvp output_bias_rom_tb.vvp
//==============================================================================
`timescale 1ns / 1ps

module output_bias_rom_tb;

    localparam ADDR_WIDTH = 1;
    localparam DEPTH      = 2;

    reg  [ADDR_WIDTH-1:0] addr;
    wire [15:0]            dout;

    integer pass_count, fail_count;
    integer i;

    output_bias_rom dut (
        .addr (addr),
        .dout (dout)
    );

    task check;
        input [255:0] name;
        input [15:0] expected;
        begin
            if (dout === expected) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : addr=%0d dout=%0d (expected %0d)",
                          name, addr, dout, expected);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        // ---- T1: full (exhaustive) address sweep ----
        for (i = 0; i < DEPTH; i = i + 1) begin
            addr = i[ADDR_WIDTH-1:0];
            #1;
            check("T1 address sweep", dut.mem[i]);
        end
        $display("[INFO] T1 complete: swept all %0d addresses (exhaustive)", DEPTH);

        // ---- T2: combinational update, no clock edge ----
        addr = 1'd0;
        #1;
        if (dout !== dut.mem[0]) begin
            fail_count = fail_count + 1;
            $display("[FAIL] T2a combinational read at addr 0 (class0 bias)");
        end else begin
            pass_count = pass_count + 1;
        end

        addr = 1'd1;
        #1;
        if (dout !== dut.mem[1]) begin
            fail_count = fail_count + 1;
            $display("[FAIL] T2b combinational read at addr 1 (class1 bias, no clock edge occurred)");
        end else begin
            pass_count = pass_count + 1;
            $display("[PASS] T2 combinational (zero-latency) read confirmed -- dout followed addr with no clock edge");
        end

        // ---- T3: read stability (same address, two reads) ----
        addr = 1'd0;
        #1;
        check("T3a read stability first read", dut.mem[0]);
        #1;
        check("T3b read stability second read", dut.mem[0]);

        // ---- summary ----
        $display("--------------------------------------------------");
        $display("output_bias_rom_tb summary: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("output_bias_rom_tb: ALL TESTS PASSED");
        else
            $display("output_bias_rom_tb: FAILURES PRESENT");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
