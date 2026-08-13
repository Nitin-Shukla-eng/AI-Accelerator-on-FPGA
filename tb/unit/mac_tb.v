//==============================================================================
// mac_tb.v
// Self-checking testbench for rtl/math/mac.v
// HDS Section 3.1 / VIS unit-test matrix, item 1 (build order: first, no
// dependencies).
//
// Covers:
//   T1 - reset drives acc_out to 0
//   T2 - single MAC step, positive operands, correct Q8.8 renormalization
//   T3 - multi-term accumulation (4 terms), matching per-term-shift-then-sum
//        (must mirror quantize_forward()'s Python reference exactly, per
//        PHASE3_NOTES.md / the Phase 3 mac.v arithmetic fix)
//   T4 - negative operand: arithmetic (sign-preserving) right shift
//   T5 - acc_clear takes priority over en when both asserted same cycle
//   T6 - acc_clear alone (no new accumulation) zeroes the accumulator
//
// Run:
//   iverilog -o mac_tb.vvp -I ../../rtl/common mac_tb.v ../../rtl/math/mac.v
//   vvp mac_tb.vvp
//==============================================================================
`timescale 1ns / 1ps
`include "../../rtl/common/parameters.vh"

module mac_tb;

    reg clk, rst;
    reg en, acc_clear;
    reg signed [`DATA_WIDTH-1:0] operand_a, operand_b;
    wire signed [`ACC_WIDTH-1:0] acc_out;

    integer pass_count, fail_count;

    mac dut (
        .clk       (clk),
        .rst       (rst),
        .en        (en),
        .acc_clear (acc_clear),
        .operand_a (operand_a),
        .operand_b (operand_b),
        .acc_out   (acc_out)
    );

    // 10ns clock period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Q8.8 helper: convert a real number to its Q8.8 integer encoding
    function signed [15:0] to_q88;
        input real val;
        begin
            to_q88 = $rtoi(val * 256.0);
        end
    endfunction

    task check_acc;
        input [255:0] name;      // test label (ASCII, sized generously)
        input signed [`ACC_WIDTH-1:0] expected;
        begin
            if (acc_out === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : acc_out=%0d (expected %0d)", name, acc_out, expected);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : acc_out=%0d (expected %0d)", name, acc_out, expected);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        en = 1'b0; acc_clear = 1'b0; operand_a = 16'sd0; operand_b = 16'sd0;

        // ---- T1: reset ----
        rst = 1'b1;
        @(posedge clk); #1;
        check_acc("T1 reset drives acc_out to 0", 32'sd0);
        rst = 1'b0;
        @(posedge clk); #1;

        // ---- T2: single MAC step, 1.0 * 2.0 = 2.0 ----
        // 1.0 in Q8.8 = 256, 2.0 in Q8.8 = 512
        // product = 256*512 = 131072 ; renormalized = 131072 >>> 8 = 512 (= 2.0 Q8.8)
        acc_clear = 1'b1;
        @(posedge clk); #1;
        acc_clear = 1'b0;
        operand_a = to_q88(1.0);
        operand_b = to_q88(2.0);
        en = 1'b1;
        @(posedge clk); #1;
        en = 1'b0;
        check_acc("T2 single MAC 1.0*2.0", 32'sd512);

        // ---- T3: accumulate 4 terms (hidden-layer-shaped), verify
        //          per-term-shift-then-sum matches hand computation ----
        // terms: (1.5 * 0.5), (2.0 * -1.0), (0.25 * 4.0), (-0.5 * -0.5)
        // Each term individually: product Q16.16 -> renormalized (>>>8) -> Q8.8
        // then summed. Compute expected using the SAME per-term-shift rule
        // the RTL uses (not sum-then-shift).
        acc_clear = 1'b1;
        @(posedge clk); #1;
        acc_clear = 1'b0;

        begin : t3_block
            reg signed [31:0] p0, p1, p2, p3;
            reg signed [31:0] r0, r1, r2, r3;
            reg signed [31:0] expected_sum;

            p0 = to_q88(1.5)  * to_q88(0.5);
            p1 = to_q88(2.0)  * to_q88(-1.0);
            p2 = to_q88(0.25) * to_q88(4.0);
            p3 = to_q88(-0.5) * to_q88(-0.5);
            r0 = p0 >>> 8;
            r1 = p1 >>> 8;
            r2 = p2 >>> 8;
            r3 = p3 >>> 8;
            expected_sum = r0 + r1 + r2 + r3;

            operand_a = to_q88(1.5);  operand_b = to_q88(0.5);  en = 1'b1;
            @(posedge clk); #1;
            operand_a = to_q88(2.0);  operand_b = to_q88(-1.0);
            @(posedge clk); #1;
            operand_a = to_q88(0.25); operand_b = to_q88(4.0);
            @(posedge clk); #1;
            operand_a = to_q88(-0.5); operand_b = to_q88(-0.5);
            @(posedge clk); #1;
            en = 1'b0;

            check_acc("T3 four-term accumulation (per-term shift order)", expected_sum);
        end

        // ---- T4: negative operand, arithmetic shift correctness ----
        // -3.0 * 2.0 = -6.0  ->  Q8.8: -768 * 512 = -393216 ; >>>8 = -1536 (-6.0)
        acc_clear = 1'b1;
        @(posedge clk); #1;
        acc_clear = 1'b0;
        operand_a = to_q88(-3.0);
        operand_b = to_q88(2.0);
        en = 1'b1;
        @(posedge clk); #1;
        en = 1'b0;
        check_acc("T4 negative operand arithmetic shift", -32'sd1536);

        // ---- T5: acc_clear priority over en in the same cycle ----
        // Accumulator currently holds -1536 from T4. Assert en and acc_clear
        // together with a nonzero product pending -- acc_clear must win.
        operand_a = to_q88(5.0);
        operand_b = to_q88(5.0);
        en = 1'b1;
        acc_clear = 1'b1;
        @(posedge clk); #1;
        en = 1'b0;
        acc_clear = 1'b0;
        check_acc("T5 acc_clear priority over en", 32'sd0);

        // ---- T6: acc_clear alone, no accumulation ----
        // Put a known nonzero value in, then clear with en low.
        operand_a = to_q88(1.0);
        operand_b = to_q88(1.0);
        en = 1'b1;
        @(posedge clk); #1;
        en = 1'b0;
        // acc_out should now be 256 (1.0*1.0). Confirm before clearing.
        check_acc("T6a pre-clear sanity (1.0*1.0)", 32'sd256);
        acc_clear = 1'b1;
        @(posedge clk); #1;
        acc_clear = 1'b0;
        check_acc("T6b acc_clear alone zeroes accumulator", 32'sd0);

        // ---- summary ----
        $display("--------------------------------------------------");
        $display("mac_tb summary: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("mac_tb: ALL TESTS PASSED");
        else
            $display("mac_tb: FAILURES PRESENT");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
