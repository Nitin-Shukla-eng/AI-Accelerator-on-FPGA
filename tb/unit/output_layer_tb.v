//==============================================================================
// output_layer_tb.v
// Self-checking testbench for rtl/accelerator/output_layer.v
// HDS Section 3.4 / VIS unit-test matrix. Build order: after hidden_layer,
// alongside the two output ROMs (instantiated here, since output_layer
// takes ROM data as INPUTS rather than owning the ROMs itself).
//
// Golden reference: same approach as hidden_layer_tb.v -- reads the actual
// weight/bias content straight out of the instantiated ROMs and runs the
// exact same arithmetic mac.v/output_layer.v use: per-term product,
// arithmetic shift by FRAC_BITS, accumulate, add bias, saturate to Q8.8.
// NO ReLU at this stage (HDS 3.4.5/3.4.8 -- raw scores compared directly).
// Mirrors quantize.py's quantize_forward() output-layer stage exactly, and
// stays valid across retraining since it never hardcodes a weight value.
//
// Covers:
//   T1 - all-zero hidden activations (sanity: scores should equal
//        saturate(bias) per class)
//   T2 - a plausible post-ReLU activation vector (non-negative, since real
//        hidden_layer output is always >= 0, but the module itself doesn't
//        assume this -- it just consumes whatever it's given)
//   T3 - a second, different activation vector
//   T4 - two back-to-back inferences (start_output re-pulsed immediately
//        after output_done, no idle gap) -- catches restart/re-trigger bugs
//   INFO - reports the observed cycle count per inference (expected ~20
//        per HDS 3.4.6: 10 cycles/class x 2 classes); reported, not hard-
//        failed, since this is a documented but non-functional timing target.
//
// FIX (see hidden_layer_tb.v for the same issue): the output_done polling
// loop now adds a #1 settling delay after each @(posedge clk) before
// re-checking the condition. output_done is a registered output updated
// via a nonblocking assignment inside the DUT; without the delay, the
// testbench's blocking read right after @(posedge clk) sees the stale
// pre-update value (NBA hasn't resolved yet in the same simulation delta),
// which can cause it to miss the single-cycle output_done pulse entirely
// and time out even though the DUT is working correctly.
//
// Run (single line -- do not use backslash line continuation on Windows):
//   iverilog -o output_layer_tb.vvp -I../../rtl/common output_layer_tb.v ../../rtl/accelerator/output_layer.v ../../rtl/math/mac.v ../../rtl/memory/output_weight_rom.v ../../rtl/memory/output_bias_rom.v
//   vvp output_layer_tb.vvp
//==============================================================================
`timescale 1ns / 1ps
`include "parameters.vh"

module output_layer_tb;

    reg clk, rst;
    reg start_output;
    reg signed [`NUM_HIDDEN*`DATA_WIDTH-1:0] hidden_act_in;

    wire [`OUTPUT_W_ADDR_WIDTH-1:0] output_w_addr;
    wire [`OUTPUT_B_ADDR_WIDTH-1:0] output_b_addr;
    wire signed [`DATA_WIDTH-1:0]    output_w_dout, output_b_dout;
    wire output_done;
    wire signed [`DATA_WIDTH-1:0] class0_score, class1_score;

    integer pass_count, fail_count;

    output_weight_rom u_w_rom (
        .addr (output_w_addr),
        .dout (output_w_dout)
    );

    output_bias_rom u_b_rom (
        .addr (output_b_addr),
        .dout (output_b_dout)
    );

    output_layer dut (
        .clk           (clk),
        .rst           (rst),
        .start_output  (start_output),
        .hidden_act_in (hidden_act_in),
        .output_w_dout (output_w_dout),
        .output_b_dout (output_b_dout),
        .output_w_addr (output_w_addr),
        .output_b_addr (output_b_addr),
        .output_done   (output_done),
        .class0_score  (class0_score),
        .class1_score  (class1_score)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function signed [15:0] to_q88;
        input real val;
        begin
            to_q88 = $rtoi(val * 256.0);
        end
    endfunction

    // Pack 8 real-valued activations into the flattened bus, matching
    // hidden_layer.v's {neuron7,...,neuron0} bit ordering convention.
    task pack_hidden_act;
        input real h0, h1, h2, h3, h4, h5, h6, h7;
        output signed [`NUM_HIDDEN*`DATA_WIDTH-1:0] packed;
        begin
            packed[1*`DATA_WIDTH-1 -: `DATA_WIDTH] = to_q88(h0);
            packed[2*`DATA_WIDTH-1 -: `DATA_WIDTH] = to_q88(h1);
            packed[3*`DATA_WIDTH-1 -: `DATA_WIDTH] = to_q88(h2);
            packed[4*`DATA_WIDTH-1 -: `DATA_WIDTH] = to_q88(h3);
            packed[5*`DATA_WIDTH-1 -: `DATA_WIDTH] = to_q88(h4);
            packed[6*`DATA_WIDTH-1 -: `DATA_WIDTH] = to_q88(h5);
            packed[7*`DATA_WIDTH-1 -: `DATA_WIDTH] = to_q88(h6);
            packed[8*`DATA_WIDTH-1 -: `DATA_WIDTH] = to_q88(h7);
        end
    endtask

    // Golden reference: reads real ROM content, applies mac.v's exact
    // per-term-shift arithmetic + saturate. NO ReLU (output stage).
    task compute_expected_output;
        input signed [`NUM_HIDDEN*`DATA_WIDTH-1:0] hidden_flat;
        output signed [15:0] exp_class0;
        output signed [15:0] exp_class1;
        integer k, j;
        reg signed [15:0] h;
        reg signed [15:0] w;
        reg signed [31:0] acc;
        reg signed [31:0] product;
        reg signed [31:0] renorm;
        reg signed [31:0] sum_wide;
        reg signed [15:0] sat;
        begin
            for (k = 0; k < `NUM_CLASSES; k = k + 1) begin
                acc = 32'sd0;
                for (j = 0; j < `NUM_HIDDEN; j = j + 1) begin
                    h = hidden_flat[(j+1)*`DATA_WIDTH-1 -: `DATA_WIDTH];
                    w = $signed(u_w_rom.mem[k*`NUM_HIDDEN + j]);
                    product = h * w;
                    renorm = product >>> `FRAC_BITS;
                    acc = acc + renorm;
                end
                sum_wide = acc + $signed(u_b_rom.mem[k]);
                if (sum_wide > 32'sd32767)
                    sat = 16'sh7FFF;
                else if (sum_wide < -32'sd32768)
                    sat = 16'sh8000;
                else
                    sat = sum_wide[15:0];

                if (k == 0)
                    exp_class0 = sat;
                else
                    exp_class1 = sat;
            end
        end
    endtask

    task run_inference;
        input real h0, h1, h2, h3, h4, h5, h6, h7;
        input [255:0] name;
        reg signed [`NUM_HIDDEN*`DATA_WIDTH-1:0] act;
        reg signed [15:0] exp_c0, exp_c1;
        integer cycles;
        begin
            pack_hidden_act(h0, h1, h2, h3, h4, h5, h6, h7, act);
            hidden_act_in = act;
            compute_expected_output(act, exp_c0, exp_c1);

            @(posedge clk);
            start_output = 1'b1;
            @(posedge clk);
            start_output = 1'b0;

            cycles = 1;
            while (!output_done && cycles < 200) begin
                @(posedge clk);
                #1; // settle past the NBA update region before sampling output_done
                cycles = cycles + 1;
            end
            #1;

            if (!output_done) begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : timed out waiting for output_done", name);
            end else if (class0_score === exp_c0 && class1_score === exp_c1) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : class0=%0d class1=%0d matches golden reference (%0d cycles)",
                          name, class0_score, class1_score, cycles);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : class0=%0d (expected %0d)  class1=%0d (expected %0d)",
                          name, class0_score, exp_c0, class1_score, exp_c1);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        start_output = 1'b0;
        hidden_act_in = 0;

        rst = 1'b1;
        @(posedge clk); @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // T1: all-zero activations
        run_inference(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "T1 all-zero activations");

        @(posedge clk);

        // T2: plausible post-ReLU activation vector (non-negative)
        run_inference(0.0, 1.0, 0.5, 0.0, 2.0, 0.25, 0.0, 1.5, "T2 post-ReLU-style vector");

        @(posedge clk);

        // T3: a second, different activation vector
        run_inference(3.0, 0.0, 0.0, 0.75, 0.0, 2.5, 1.0, 0.0, "T3 second activation vector");

        // T4: two back-to-back inferences, NO idle gap between them
        run_inference(1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, "T4a back-to-back inference 1");
        run_inference(0.5, 0.0, 1.5, 0.0, 0.5, 0.0, 1.5, 0.0, "T4b back-to-back inference 2 (no idle gap)");

        // ---- summary ----
        $display("--------------------------------------------------");
        $display("output_layer_tb summary: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("output_layer_tb: ALL TESTS PASSED");
        else
            $display("output_layer_tb: FAILURES PRESENT");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
