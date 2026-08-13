//==============================================================================
// hidden_bias_rom_tb.v
// Self-checking testbench for generated/hardware/hidden_bias_rom.v
// HDS Section 3.8 / VIS unit-test matrix.
//
// Same rationale as hidden_weight_rom_tb.v: checks addressing/timing
// behavior against the module's own stored content, not hardcoded bias
// values, so it stays valid across retraining.
//   T1 - full address sweep (8 entries): dout matches dut.mem[addr]
//   T2 - truly combinational: dout updates with no clock edge
//   T3 - read stability: same address read twice returns the same value
//
// Run:
//   iverilog -o hidden_bias_rom_tb.vvp hidden_bias_rom_tb.v \
//       ../../rtl/memory/hidden_bias_rom.v
//   vvp hidden_bias_rom_tb.vvp
//==============================================================================
`timescale 1ns / 1ps

module hidden_bias_rom_tb;

    localparam ADDR_WIDTH = 3;
    localparam DEPTH      = 8;

    reg  [ADDR_WIDTH-1:0] addr;
    wire [15:0]            dout;

    integer pass_count, fail_count;
    integer i;

    hidden_bias_rom dut (
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

        // ---- T1: full address sweep against the module's own mem[] ----
        for (i = 0; i < DEPTH; i = i + 1) begin
            addr = i[ADDR_WIDTH-1:0];
            #1;
            check("T1 address sweep", dut.mem[i]);
        end
        $display("[INFO] T1 complete: swept all %0d addresses", DEPTH);

        // ---- T2: combinational update, no clock edge ----
        addr = 3'd0;
        #1;
        if (dout !== dut.mem[0]) begin
            fail_count = fail_count + 1;
            $display("[FAIL] T2a combinational read at addr 0");
        end else begin
            pass_count = pass_count + 1;
        end

        addr = 3'd7;
        #1;
        if (dout !== dut.mem[7]) begin
            fail_count = fail_count + 1;
            $display("[FAIL] T2b combinational read at addr 7 (no clock edge occurred)");
        end else begin
            pass_count = pass_count + 1;
            $display("[PASS] T2 combinational (zero-latency) read confirmed -- dout followed addr with no clock edge");
        end

        // ---- T3: read stability (same address, two reads) ----
        addr = 3'd4;
        #1;
        check("T3a read stability first read", dut.mem[4]);
        #1;
        check("T3b read stability second read", dut.mem[4]);

        // ---- summary ----
        $display("--------------------------------------------------");
        $display("hidden_bias_rom_tb summary: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("hidden_bias_rom_tb: ALL TESTS PASSED");
        else
            $display("hidden_bias_rom_tb: FAILURES PRESENT");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
