//==============================================================================
// hidden_layer_tb.v
// Self-checking testbench for rtl/accelerator/hidden_layer.v
// HDS Section 3.3 / VIS unit-test matrix. Build order: after mac, relu,
// and the two hidden ROMs (all instantiated here, since hidden_layer takes
// ROM data as INPUTS rather than owning the ROMs itself).
//
// Golden reference: computed INSIDE this testbench by reading the actual
// weight/bias content straight out of the instantiated ROMs (hierarchical
// reference into their internal mem[] arrays) and running the exact same
// arithmetic mac.v/hidden_layer.v use: per-term product, arithmetic shift
// by FRAC_BITS, accumulate, add bias, saturate to Q8.8, then ReLU. This
// mirrors quantize.py's quantize_forward() exactly (see PHASE3_NOTES.md /
// the Phase 3 mac.v arithmetic fix) and stays valid across retraining,
// since it never hardcodes a weight value.
//
// Covers:
//   T1 - all-zero features (sanity: activations should equal relu(bias) per neuron)
//   T2 - a mixed positive/negative feature vector
//   T3 - a second, different feature vector (different neurons' signs will flip)
//   T4 - two back-to-back inferences (start_hidden re-pulsed immediately
//        after hidden_done, no idle gap) -- catches restart/re-trigger bugs
//   INFO - reports the observed cycle count per inference (expected ~56
//        per HDS 3.3.6 / PHASE3_NOTES.md's no-bias-fold baseline: 7
//        cycles/neuron x 8 neurons); reported, not hard-failed, since this
//        is a documented but non-functional timing target.
//
// DEBUG: this version includes a cycle-by-cycle FSM trace (first 70 cycles)
// to diagnose the "timed out waiting for hidden_done" failures. Remove the
// DEBUG block once the root cause is found and fixed.
//
// Run:
//   iverilog -o hidden_layer_tb.vvp -I../../rtl/common hidden_layer_tb.v ^
//       ../../rtl/accelerator/hidden_layer.v ../../rtl/math/mac.v ^
//       ../../rtl/math/relu.v ../../rtl/memory/hidden_weight_rom.v ^
//       ../../rtl/memory/hidden_bias_rom.v
//   vvp hidden_layer_tb.vvp
//==============================================================================
`timescale 1ns / 1ps
`include "../../rtl/common/parameters.vh"

module hidden_layer_tb;

    reg clk, rst;
    reg start_hidden;
    reg signed [`DATA_WIDTH-1:0] feature0, feature1, feature2, feature3;

    wire [`HIDDEN_W_ADDR_WIDTH-1:0] hidden_w_addr;
    wire [`HIDDEN_B_ADDR_WIDTH-1:0] hidden_b_addr;
    wire signed [`DATA_WIDTH-1:0]    hidden_w_dout, hidden_b_dout;
    wire hidden_done;
    wire signed [`NUM_HIDDEN*`DATA_WIDTH-1:0] hidden_act_out;

    integer pass_count, fail_count;

    hidden_weight_rom u_w_rom (
        .addr (hidden_w_addr),
        .dout (hidden_w_dout)
    );

    hidden_bias_rom u_b_rom (
        .addr (hidden_b_addr),
        .dout (hidden_b_dout)
    );

    hidden_layer dut (
        .clk            (clk),
        .rst            (rst),
        .start_hidden   (start_hidden),
        .feature0       (feature0),
        .feature1       (feature1),
        .feature2       (feature2),
        .feature3       (feature3),
        .hidden_w_dout  (hidden_w_dout),
        .hidden_b_dout  (hidden_b_dout),
        .hidden_w_addr  (hidden_w_addr),
        .hidden_b_addr  (hidden_b_addr),
        .hidden_done    (hidden_done),
        .hidden_act_out (hidden_act_out)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function signed [15:0] to_q88;
        input real val;
        begin
            to_q88 = $rtoi(val * 256.0);
        end
    endfunction

    // Golden reference: reads real ROM content, applies mac.v's exact
    // per-term-shift arithmetic + saturate + ReLU.
    task compute_expected_hidden;
        input signed [15:0] f0, f1, f2, f3;
        output [`NUM_HIDDEN*`DATA_WIDTH-1:0] expected_flat;
        integer j, i;
        reg signed [15:0] feat_arr [0:3];
        reg signed [31:0] acc;
        reg signed [31:0] product;
        reg signed [31:0] renorm;
        reg signed [31:0] sum_wide;
        reg signed [15:0] sat;
        reg signed [15:0] relu_val;
        reg signed [15:0] w;
        begin
            feat_arr[0] = f0; feat_arr[1] = f1; feat_arr[2] = f2; feat_arr[3] = f3;
            for (j = 0; j < `NUM_HIDDEN; j = j + 1) begin
                acc = 32'sd0;
                for (i = 0; i < `NUM_FEATURES; i = i + 1) begin
                    w = $signed(u_w_rom.mem[j*`NUM_FEATURES + i]);
                    product = feat_arr[i] * w;
                    renorm = product >>> `FRAC_BITS;
                    acc = acc + renorm;
                end
                sum_wide = acc + $signed(u_b_rom.mem[j]);
                if (sum_wide > 32'sd32767)
                    sat = 16'sh7FFF;
                else if (sum_wide < -32'sd32768)
                    sat = 16'sh8000;
                else
                    sat = sum_wide[15:0];
                relu_val = sat[15] ? 16'sd0 : sat;
                expected_flat[(j+1)*`DATA_WIDTH-1 -: `DATA_WIDTH] = relu_val;
            end
        end
    endtask

    task run_inference;
        input signed [15:0] f0, f1, f2, f3;
        input [255:0] name;
        reg [`NUM_HIDDEN*`DATA_WIDTH-1:0] expected;
        integer cycles;
        begin
            feature0 = f0; feature1 = f1; feature2 = f2; feature3 = f3;
            compute_expected_hidden(f0, f1, f2, f3, expected);

            @(posedge clk);
            start_hidden = 1'b1;
            @(posedge clk);
            start_hidden = 1'b0;

            cycles = 1;
            while (!hidden_done && cycles < 200) begin
                @(posedge clk);
                #1; // settle past the NBA update region before sampling hidden_done
                cycles = cycles + 1;
            end

            if (!hidden_done) begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : timed out waiting for hidden_done", name);
            end else if (hidden_act_out === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : hidden_act_out matches golden reference (%0d cycles)", name, cycles);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : hidden_act_out=%h expected=%h", name, hidden_act_out, expected);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        start_hidden = 1'b0;
        feature0 = 0; feature1 = 0; feature2 = 0; feature3 = 0;

        rst = 1'b1;
        @(posedge clk); @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // T1: all-zero features
        run_inference(to_q88(0.0), to_q88(0.0), to_q88(0.0), to_q88(0.0), "T1 all-zero features");

        // settle a cycle between inferences
        @(posedge clk);

        // T2: mixed positive/negative feature vector
        run_inference(to_q88(1.0), to_q88(-1.0), to_q88(0.5), to_q88(-0.5), "T2 mixed feature vector");

        @(posedge clk);

        // T3: a different feature vector (larger magnitudes)
        run_inference(to_q88(2.5), to_q88(-3.0), to_q88(0.75), to_q88(1.25), "T3 second feature vector");

        // T4: two back-to-back inferences, NO idle gap between them --
        // start the second immediately on the cycle after hidden_done.
        run_inference(to_q88(-2.0), to_q88(1.5), to_q88(-0.25), to_q88(2.0), "T4a back-to-back inference 1");
        run_inference(to_q88(0.5),  to_q88(0.5), to_q88(0.5),  to_q88(0.5), "T4b back-to-back inference 2 (no idle gap)");

        // ---- summary ----
        $display("--------------------------------------------------");
        $display("hidden_layer_tb summary: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("hidden_layer_tb: ALL TESTS PASSED");
        else
            $display("hidden_layer_tb: FAILURES PRESENT");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
