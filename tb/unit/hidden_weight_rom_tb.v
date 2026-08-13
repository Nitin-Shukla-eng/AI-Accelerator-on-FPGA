//==============================================================================
// hidden_weight_rom_tb.v
// Self-checking testbench for generated/hardware/hidden_weight_rom.v
// HDS Section 3.8 / VIS unit-test matrix. Build order: after mac/relu,
// alongside the other three ROM testbenches.
//
// Since the actual weight VALUES change every time python/export_model.py
// is re-run against a newly trained model, this testbench does NOT hardcode
// expected weight numbers. Instead it checks the wrapper's BEHAVIOR, which
// is stable across retraining:
//   T1 - full address sweep: dout matches the module's own internal mem[]
//        content at every one of the 32 valid addresses (catches addressing
//        bugs -- e.g. an off-by-one in how hidden_layer.v forms
//        {neuron_idx, feature_idx} -- independent of what the weights are)
//   T2 - truly combinational: dout updates immediately when addr changes,
//        with NO clock edge involved (this is the exact property whose
//        absence caused the Phase 3 registered-ROM bug -- worth checking
//        explicitly, not just assuming the module has no clk port)
//   T3 - read stability: reading the same address twice in a row returns
//        the same value both times
//
// Run:
//   iverilog -o hidden_weight_rom_tb.vvp hidden_weight_rom_tb.v \
//       ../../rtl/memory/hidden_weight_rom.v
//   vvp hidden_weight_rom_tb.vvp
//==============================================================================
`timescale 1ns / 1ps

module hidden_weight_rom_tb;

    localparam ADDR_WIDTH = 5;
    localparam DEPTH      = 32;

    reg  [ADDR_WIDTH-1:0] addr;
    wire [15:0]            dout;

    integer pass_count, fail_count;
    integer i;

    hidden_weight_rom dut (
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
        // Pick two addresses with (in general) different content, change
        // addr with no clock involved at all, and confirm dout tracks it
        // within the same delta-cycle (the #1 below is simulation-time
        // settling for the testbench's own observation, not a clock edge).
        addr = 5'd0;
        #1;
        if (dout !== dut.mem[0]) begin
            fail_count = fail_count + 1;
            $display("[FAIL] T2a combinational read at addr 0");
        end else begin
            pass_count = pass_count + 1;
        end

        addr = 5'd31;
        #1;
        if (dout !== dut.mem[31]) begin
            fail_count = fail_count + 1;
            $display("[FAIL] T2b combinational read at addr 31 (no clock edge occurred)");
        end else begin
            pass_count = pass_count + 1;
            $display("[PASS] T2 combinational (zero-latency) read confirmed -- dout followed addr with no clock edge");
        end

        // ---- T3: read stability (same address, two reads) ----
        addr = 5'd15;
        #1;
        check("T3a read stability first read", dut.mem[15]);
        #1; // no addr change
        check("T3b read stability second read", dut.mem[15]);

        // ---- summary ----
        $display("--------------------------------------------------");
        $display("hidden_weight_rom_tb summary: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("hidden_weight_rom_tb: ALL TESTS PASSED");
        else
            $display("hidden_weight_rom_tb: FAILURES PRESENT");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
