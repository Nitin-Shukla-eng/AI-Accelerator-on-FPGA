//==============================================================================
// output_weight_rom_tb.v
// Self-checking testbench for generated/hardware/output_weight_rom.v
// HDS Section 3.8 / VIS unit-test matrix.
//
// Same rationale as hidden_weight_rom_tb.v: checks addressing/timing
// behavior against the module's own stored content, not hardcoded weight
// values, so it stays valid across retraining.
//   T1 - full address sweep (16 entries): dout matches dut.mem[addr]
//   T2 - truly combinational: dout updates with no clock edge
//   T3 - read stability: same address read twice returns the same value
//   T4 - addressing convention spot-check: address 0 = class0/hidden0 and
//        address 8 = class1/hidden0 (per output_layer.v's
//        {class_idx, hidden_idx} = class_idx*8 + hidden_idx convention) --
//        both must be independently readable and, in general, distinct
//        entries (catches an addr-width/class-boundary mixup even without
//        knowing the actual weight values)
//
// Run:
//   iverilog -o output_weight_rom_tb.vvp output_weight_rom_tb.v \
//       ../../rtl/memory/output_weight_rom.v
//   vvp output_weight_rom_tb.vvp
//==============================================================================
`timescale 1ns / 1ps

module output_weight_rom_tb;

    localparam ADDR_WIDTH = 4;
    localparam DEPTH      = 16;

    reg  [ADDR_WIDTH-1:0] addr;
    wire [15:0]            dout;

    integer pass_count, fail_count;
    integer i;

    output_weight_rom dut (
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
        addr = 4'd0;
        #1;
        if (dout !== dut.mem[0]) begin
            fail_count = fail_count + 1;
            $display("[FAIL] T2a combinational read at addr 0");
        end else begin
            pass_count = pass_count + 1;
        end

        addr = 4'd15;
        #1;
        if (dout !== dut.mem[15]) begin
            fail_count = fail_count + 1;
            $display("[FAIL] T2b combinational read at addr 15 (no clock edge occurred)");
        end else begin
            pass_count = pass_count + 1;
            $display("[PASS] T2 combinational (zero-latency) read confirmed -- dout followed addr with no clock edge");
        end

        // ---- T3: read stability (same address, two reads) ----
        addr = 4'd9;
        #1;
        check("T3a read stability first read", dut.mem[9]);
        #1;
        check("T3b read stability second read", dut.mem[9]);

        // ---- T4: class-boundary addressing spot-check ----
        // addr=0  -> class_idx=0, hidden_idx=0 (class0*8+0)
        // addr=8  -> class_idx=1, hidden_idx=0 (class1*8+0)
        // These two entries are independently stored and, for a real
        // trained model, will (almost certainly) differ -- this is a
        // best-effort structural check, not a functional guarantee, so it
        // only reports an informational note rather than a failure if they
        // happen to coincide.
        addr = 4'd0;
        #1;
        begin : t4_block
            reg [15:0] class0_hidden0;
            reg [15:0] class1_hidden0;
            class0_hidden0 = dout;
            addr = 4'd8;
            #1;
            class1_hidden0 = dout;
            if (class0_hidden0 !== dut.mem[0] || class1_hidden0 !== dut.mem[8]) begin
                fail_count = fail_count + 1;
                $display("[FAIL] T4 class-boundary addressing mismatch");
            end else begin
                pass_count = pass_count + 1;
                $display("[PASS] T4 class-boundary addressing: addr 0 (class0,hidden0)=%0d, addr 8 (class1,hidden0)=%0d",
                          $signed(class0_hidden0), $signed(class1_hidden0));
                if (class0_hidden0 === class1_hidden0)
                    $display("[INFO] T4 note: class0/class1 weight at hidden0 happen to be numerically equal -- not a failure, just worth knowing");
            end
        end

        // ---- summary ----
        $display("--------------------------------------------------");
        $display("output_weight_rom_tb summary: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("output_weight_rom_tb: ALL TESTS PASSED");
        else
            $display("output_weight_rom_tb: FAILURES PRESENT");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
