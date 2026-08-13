//==============================================================================
// controller_fsm_tb.v
// Self-checking testbench for rtl/accelerator/controller_fsm.v
// HDS Section 3.5 / VIS unit-test matrix. Build order: after
// hidden_layer/output_layer's start/done handshake convention is fixed
// (this module has no RTL dependencies of its own -- pure sequencer).
//
// controller_fsm has NO data path (confirmed by re-checking
// tinyml_accelerator_top.v: FEATURE0-3 wire directly, unlatched, into
// hidden_layer), so this testbench drives hidden_done/output_done directly
// from the testbench itself, standing in for hidden_layer/output_layer.
//
// Covers:
//   T1 - reset: S_IDLE, busy=0, done=0, all pulses low
//   T2 - start_bit in S_IDLE -> S_LOAD (busy=1) the next cycle
//   T3 - S_LOAD -> S_HIDDEN unconditional, one cycle later; start_hidden
//        asserted during S_HIDDEN while hidden_done=0
//   T4 - hidden_done pulses -> start_hidden deasserts the SAME cycle
//        (critical: this is the exact mechanism that prevents hidden_layer
//        from seeing a stale start_hidden and immediately restarting) ->
//        S_HIDDEN -> S_OUTPUT the next cycle
//   T5 - start_output asserted during S_OUTPUT while output_done=0;
//        output_done pulses -> start_output deasserts the same cycle,
//        latch_prediction pulses the same cycle -> S_OUTPUT -> S_DONE
//   T6 - S_DONE holds: busy=0, done=1, latch_prediction=0, and STAYS
//        asserted across multiple cycles (poll-friendly for software)
//   T7 - back-to-back inference: start_bit pulsed while in S_DONE ->
//        S_LOAD directly (S_IDLE is skipped), done drops to 0
//   T8 - SOFT_RESET from mid-computation (S_HIDDEN, hidden_done=0) forces
//        S_IDLE the very next cycle, with start_hidden/start_output/
//        latch_prediction all forced low that same cycle regardless of
//        hidden_done/output_done
//   T9 - SOFT_RESET held high across a simultaneous start_bit pulse:
//        the FSM must stay in S_IDLE (SOFT_RESET overrides START)
//
// Run (single line):
//   iverilog -o controller_fsm_tb.vvp controller_fsm_tb.v ../../rtl/accelerator/controller_fsm.v
//   vvp controller_fsm_tb.vvp
//==============================================================================
`timescale 1ns / 1ps
`include "defines.vh"

module controller_fsm_tb;

    reg clk, rst;
    reg start_bit, soft_reset_bit;
    reg hidden_done, output_done;

    wire start_hidden, start_output;
    wire busy, done, latch_prediction;

    integer pass_count, fail_count;

    controller_fsm dut (
        .clk               (clk),
        .rst               (rst),
        .start_bit         (start_bit),
        .soft_reset_bit    (soft_reset_bit),
        .hidden_done       (hidden_done),
        .output_done       (output_done),
        .start_hidden      (start_hidden),
        .start_output      (start_output),
        .busy              (busy),
        .done              (done),
        .latch_prediction  (latch_prediction)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check;
        input [255:0] name;
        input actual;
        input expected;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s (state_q=%0d)", name, dut.state_q);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : actual=%0d expected=%0d (state_q=%0d)",
                          name, actual, expected, dut.state_q);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        start_bit = 1'b0;
        soft_reset_bit = 1'b0;
        hidden_done = 1'b0;
        output_done = 1'b0;

        // ---- T1: reset ----
        rst = 1'b1;
        @(posedge clk); #1;
        check("T1a reset: busy=0", busy, 1'b0);
        check("T1b reset: done=0", done, 1'b0);
        check("T1c reset: start_hidden=0", start_hidden, 1'b0);
        check("T1d reset: start_output=0", start_output, 1'b0);
        check("T1e reset: latch_prediction=0", latch_prediction, 1'b0);
        rst = 1'b0;

        // ---- T2: start_bit in S_IDLE -> S_LOAD ----
        start_bit = 1'b1;
        @(posedge clk); #1;
        start_bit = 1'b0;
        check("T2 S_IDLE + start_bit -> S_LOAD (busy=1)", busy, 1'b1);

        // ---- T3: S_LOAD -> S_HIDDEN, start_hidden asserted ----
        @(posedge clk); #1;
        check("T3a S_LOAD -> S_HIDDEN (busy still 1)", busy, 1'b1);
        check("T3b start_hidden asserted (hidden_done=0)", start_hidden, 1'b1);

        // hold a couple more cycles with hidden_done still 0 -- start_hidden
        // should stay asserted the whole dwell
        @(posedge clk); #1;
        check("T3c start_hidden still asserted mid-S_HIDDEN", start_hidden, 1'b1);

        // ---- T4: hidden_done pulses -> start_hidden deasserts SAME cycle ----
        hidden_done = 1'b1;
        #1; // combinational settle, still same cycle as hidden_done went high
        check("T4a start_hidden deasserts the SAME cycle hidden_done pulses", start_hidden, 1'b0);
        @(posedge clk); #1;
        hidden_done = 1'b0;
        check("T4b S_HIDDEN -> S_OUTPUT the cycle after hidden_done", busy, 1'b1);
        check("T4c start_output now asserted (output_done=0)", start_output, 1'b1);

        // ---- T5: output_done pulses -> start_output deasserts, latch_prediction pulses ----
        output_done = 1'b1;
        #1;
        check("T5a start_output deasserts the SAME cycle output_done pulses", start_output, 1'b0);
        check("T5b latch_prediction pulses the SAME cycle output_done pulses", latch_prediction, 1'b1);
        @(posedge clk); #1;
        output_done = 1'b0;
        check("T5c S_OUTPUT -> S_DONE the cycle after output_done", done, 1'b1);

        // ---- T6: S_DONE holds across multiple cycles ----
        check("T6a S_DONE: busy=0", busy, 1'b0);
        check("T6b S_DONE: latch_prediction=0 (not held from T5)", latch_prediction, 1'b0);
        @(posedge clk); #1;
        check("T6c S_DONE holds: done still 1 after another cycle", done, 1'b1);
        @(posedge clk); #1;
        check("T6d S_DONE holds: done still 1 after yet another cycle", done, 1'b1);

        // ---- T7: back-to-back inference, S_DONE -> S_LOAD directly ----
        start_bit = 1'b1;
        @(posedge clk); #1;
        start_bit = 1'b0;
        check("T7a S_DONE + start_bit -> S_LOAD (busy=1)", busy, 1'b1);
        check("T7b done drops to 0 once back in S_LOAD", done, 1'b0);

        // Drive it through S_HIDDEN so we're mid-computation for T8
        @(posedge clk); #1; // now in S_HIDDEN
        check("T7c confirm back in S_HIDDEN", start_hidden, 1'b1);

        // ---- T8: SOFT_RESET mid-computation (S_HIDDEN, hidden_done still 0) ----
        soft_reset_bit = 1'b1;
        #1; // combinational override, same cycle
        check("T8a start_hidden forced low the same cycle SOFT_RESET asserts", start_hidden, 1'b0);
        @(posedge clk); #1;
        check("T8b SOFT_RESET -> S_IDLE the next cycle: busy=0", busy, 1'b0);
        check("T8c SOFT_RESET -> S_IDLE the next cycle: done=0", done, 1'b0);

        // ---- T9: SOFT_RESET held high overrides a simultaneous start_bit ----
        start_bit = 1'b1; // soft_reset_bit is still 1'b1 from T8
        @(posedge clk); #1;
        check("T9a SOFT_RESET still held: start_bit ignored, busy=0", busy, 1'b0);
        @(posedge clk); #1;
        check("T9b SOFT_RESET still held: still ignored on a second cycle", busy, 1'b0);
        start_bit = 1'b0;
        soft_reset_bit = 1'b0;

        // confirm normal operation resumes once SOFT_RESET is released
        start_bit = 1'b1;
        @(posedge clk); #1;
        start_bit = 1'b0;
        check("T9c SOFT_RESET released: start_bit now takes effect (busy=1)", busy, 1'b1);

        // ---- summary ----
        $display("--------------------------------------------------");
        $display("controller_fsm_tb summary: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("controller_fsm_tb: ALL TESTS PASSED");
        else
            $display("controller_fsm_tb: FAILURES PRESENT");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
