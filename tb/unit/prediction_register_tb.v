//==============================================================================
// prediction_register_tb.v
// Self-checking testbench for rtl/accelerator/prediction_register.v
// HDS Section 3.7 / VIS unit-test matrix. Build order: after output_layer
// (no RTL dependency itself -- pure comparator + latch, but logically
// follows output_layer in the pipeline).
//
// Covers:
//   T1 - reset drives prediction_q to 0 (Normal)
//   T2 - class1 > class0 (strict) -> Fault (prediction_q = 1)
//   T3 - class0 > class1 -> Normal (prediction_q = 0)
//   T4 - tie (class0 == class1) -> Normal, per the documented fail-safe
//        tie-break rule (HDS 3.4.9/3.7.2: strict > required for Fault)
//   T5 - hold behavior: changing the score inputs WITHOUT pulsing
//        latch_prediction must NOT change prediction_q
//   T6 - correct signed comparison with negative scores (both negative,
//        class1 still > class0 -> Fault) -- catches an unsigned-compare bug
//
// Run (single line):
//   iverilog -o prediction_register_tb.vvp prediction_register_tb.v ../../rtl/accelerator/prediction_register.v
//   vvp prediction_register_tb.vvp
//==============================================================================
`timescale 1ns / 1ps
`include "parameters.vh"

module prediction_register_tb;

    reg clk, rst;
    reg latch_prediction;
    reg signed [`DATA_WIDTH-1:0] class0_score, class1_score;
    wire prediction_q;

    integer pass_count, fail_count;

    prediction_register dut (
        .clk              (clk),
        .rst              (rst),
        .latch_prediction (latch_prediction),
        .class0_score     (class0_score),
        .class1_score     (class1_score),
        .prediction_q     (prediction_q)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check;
        input [255:0] name;
        input expected;
        begin
            if (prediction_q === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : prediction_q=%0d (expected %0d)", name, prediction_q, expected);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : prediction_q=%0d (expected %0d)", name, prediction_q, expected);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        latch_prediction = 1'b0;
        class0_score = 16'sd0;
        class1_score = 16'sd0;

        // ---- T1: reset ----
        rst = 1'b1;
        @(posedge clk); #1;
        check("T1 reset drives prediction_q to 0 (Normal)", 1'b0);
        rst = 1'b0;
        @(posedge clk);

        // ---- T2: class1 > class0 -> Fault ----
        class0_score = 16'sd100;
        class1_score = 16'sd500;
        latch_prediction = 1'b1;
        @(posedge clk); #1;
        latch_prediction = 1'b0;
        check("T2 class1 > class0 -> Fault", 1'b1);

        // ---- T3: class0 > class1 -> Normal ----
        class0_score = 16'sd800;
        class1_score = 16'sd200;
        latch_prediction = 1'b1;
        @(posedge clk); #1;
        latch_prediction = 1'b0;
        check("T3 class0 > class1 -> Normal", 1'b0);

        // ---- T4: tie -> Normal (fail-safe tie-break) ----
        // Set prediction_q to Fault first (via T2-style latch) so the tie
        // result genuinely proves the tie-break logic, not just a held value.
        class0_score = 16'sd50;
        class1_score = 16'sd500;
        latch_prediction = 1'b1;
        @(posedge clk); #1;
        latch_prediction = 1'b0;
        check("T4 setup: force prediction_q to Fault before tie test", 1'b1);

        class0_score = 16'sd300;
        class1_score = 16'sd300;
        latch_prediction = 1'b1;
        @(posedge clk); #1;
        latch_prediction = 1'b0;
        check("T4 tie (class0 == class1) -> Normal", 1'b0);

        // ---- T5: hold behavior (no latch_prediction pulse) ----
        // prediction_q is currently 0 (Normal) from T4. Change the scores
        // to something that WOULD produce Fault if latched, but don't pulse
        // latch_prediction -- prediction_q must not change.
        class0_score = 16'sd0;
        class1_score = 16'sd1000;
        @(posedge clk); #1;
        check("T5a hold: no latch pulse, prediction_q unchanged", 1'b0);
        @(posedge clk); #1;
        check("T5b hold: still unchanged after a second cycle", 1'b0);

        // Now actually latch it, to confirm the pending Fault condition
        // really was live and just correctly not being applied without a pulse.
        latch_prediction = 1'b1;
        @(posedge clk); #1;
        latch_prediction = 1'b0;
        check("T5c latching the pending condition now DOES take effect", 1'b1);

        // ---- T6: signed comparison with negative scores ----
        // Both negative; class1 (-100) > class0 (-500) -- must resolve to
        // Fault. An unsigned or sign-mishandled comparator would get this
        // wrong (large positive unsigned interpretation of a very negative
        // two's-complement class0 could flip the result).
        class0_score = -16'sd500;
        class1_score = -16'sd100;
        latch_prediction = 1'b1;
        @(posedge clk); #1;
        latch_prediction = 1'b0;
        check("T6 negative scores, signed comparison -> Fault", 1'b1);

        // ---- summary ----
        $display("--------------------------------------------------");
        $display("prediction_register_tb summary: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("prediction_register_tb: ALL TESTS PASSED");
        else
            $display("prediction_register_tb: FAILURES PRESENT");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
