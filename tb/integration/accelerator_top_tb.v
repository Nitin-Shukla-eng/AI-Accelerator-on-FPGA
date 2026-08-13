//==============================================================================
// accelerator_top_tb.v
// Integration testbench for rtl/top/tinyml_accelerator_top.v
// HDS Chapter 10 / VIS integration-test matrix. First integration-level
// test: drives the accelerator EXACTLY the way firmware will (Phase 5) --
// write FEATURE0-3, pulse CONTROL.START, poll STATUS.DONE, read RESULT --
// through the same CPU register bus interface soc_top will present.
//
// Test data: the 20 real test vectors and their golden-reference expected
// predictions embedded below are copied verbatim from
// generated/software/test_vectors.h / expected_outputs.h, produced by
// python/export_model.py from the actual trained CWRU bearing-fault model
// (see quantize.py's quantize_forward() -- the golden-reference math this
// data was generated with matches mac.v's per-term-shift arithmetic
// exactly, per the Phase 3 fix). If you retrain and re-export, regenerate
// this array from the new test_vectors.h/expected_outputs.h -- it is NOT
// automatically kept in sync (unlike the ROM testbenches, this one
// necessarily hardcodes model-specific values, since it's testing
// end-to-end prediction correctness, not addressing/timing behavior).
//
// Covers:
//   - all 20 real test vectors, each independently: write features, pulse
//     START, poll DONE, read RESULT, compare to the golden expected class
//   - BUSY is asserted (STATUS bit1) at some point while polling (sanity
//     that the handshake is actually doing multi-cycle work, not just
//     returning stale/default data)
//   - back-to-back vectors with no idle gap between inferences (vector N+1's
//     FEATURE writes start immediately after vector N's RESULT read)
//
// FIX: run_vector now waits one extra @(posedge clk) after pulsing
// CONTROL.START, before beginning the STATUS polling loop. Without this,
// the very first bus_read(STATUS) happened too soon -- before
// controller_fsm had a real clock edge to leave its previous DONE state
// -- so it was reading STALE status/result left over from the prior
// vector (0 cycles observed, BUSY never seen, and an incorrect/coincidental
// prediction reused from 1-2 vectors earlier). This caused every
// odd-indexed vector to silently read garbage while the real computation
// for that vector kept running in the background and only got "seen"
// (misattributed) on the following vector's poll.
//
// Run (single line):
//   iverilog -o accelerator_top_tb.vvp -I../../rtl/common accelerator_top_tb.v ../../rtl/top/tinyml_accelerator_top.v ../../rtl/accelerator/accelerator_registers.v ../../rtl/accelerator/controller_fsm.v ../../rtl/accelerator/hidden_layer.v ../../rtl/accelerator/output_layer.v ../../rtl/accelerator/prediction_register.v ../../rtl/math/mac.v ../../rtl/math/relu.v ../../rtl/memory/hidden_weight_rom.v ../../rtl/memory/hidden_bias_rom.v ../../rtl/memory/output_weight_rom.v ../../rtl/memory/output_bias_rom.v
//   vvp accelerator_top_tb.vvp
//==============================================================================
`timescale 1ns / 1ps
`include "parameters.vh"
`include "types.vh"

module accelerator_top_tb;

    localparam NUM_VECTORS = 20;

    localparam ADDR_CONTROL  = 5'h00;
    localparam ADDR_STATUS   = 5'h04;
    localparam ADDR_FEATURE0 = 5'h08;
    localparam ADDR_FEATURE1 = 5'h0C;
    localparam ADDR_FEATURE2 = 5'h10;
    localparam ADDR_FEATURE3 = 5'h14;
    localparam ADDR_RESULT   = 5'h18;

    reg clk, rst;
    reg [4:0]  reg_addr;
    reg [31:0] reg_wdata;
    reg        reg_wen, reg_ren;
    wire [31:0] reg_rdata;

    integer pass_count, fail_count;
    integer i;
    reg saw_busy;

    // ---- real test vectors, copied verbatim from generated/software/ ----
    reg signed [15:0] tv_f0 [0:NUM_VECTORS-1];
    reg signed [15:0] tv_f1 [0:NUM_VECTORS-1];
    reg signed [15:0] tv_f2 [0:NUM_VECTORS-1];
    reg signed [15:0] tv_f3 [0:NUM_VECTORS-1];
    reg                expected [0:NUM_VECTORS-1];

    tinyml_accelerator_top dut (
        .clk       (clk),
        .rst       (rst),
        .reg_addr  (reg_addr),
        .reg_wdata (reg_wdata),
        .reg_wen   (reg_wen),
        .reg_ren   (reg_ren),
        .reg_rdata (reg_rdata)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        tv_f0[0]=-165; tv_f1[0]=-156; tv_f2[0]=-138; tv_f3[0]=-194; expected[0]=0;
        tv_f0[1]=  12; tv_f1[1]= 169; tv_f2[1]= 701; tv_f3[1]= 751; expected[1]=1;
        tv_f0[2]=-160; tv_f1[2]=-153; tv_f2[2]=-128; tv_f3[2]=-181; expected[2]=0;
        tv_f0[3]= -86; tv_f1[3]= -76; tv_f2[3]= -85; tv_f3[3]=  82; expected[3]=1;
        tv_f0[4]=-161; tv_f1[4]=-151; tv_f2[4]=-131; tv_f3[4]=-158; expected[4]=0;
        tv_f0[5]=-163; tv_f1[5]=-151; tv_f2[5]=-133; tv_f3[5]=-149; expected[5]=0;
        tv_f0[6]=-145; tv_f1[6]=-148; tv_f2[6]=-144; tv_f3[6]=-195; expected[6]=0;
        tv_f0[7]= -91; tv_f1[7]= -73; tv_f2[7]= -55; tv_f3[7]= 118; expected[7]=1;
        tv_f0[8]=-163; tv_f1[8]=-148; tv_f2[8]=-120; tv_f3[8]=-124; expected[8]=0;
        tv_f0[9]=-151; tv_f1[9]=-143; tv_f2[9]=-130; tv_f3[9]=-130; expected[9]=0;
        tv_f0[10]= 195; tv_f1[10]= 138; tv_f2[10]=  38; tv_f3[10]= 131; expected[10]=1;
        tv_f0[11]=-159; tv_f1[11]=-154; tv_f2[11]=-132; tv_f3[11]=-197; expected[11]=0;
        tv_f0[12]= -96; tv_f1[12]=-116; tv_f2[12]=-120; tv_f3[12]=-122; expected[12]=1;
        tv_f0[13]= 173; tv_f1[13]=  75; tv_f2[13]= -38; tv_f3[13]=  20; expected[13]=1;
        tv_f0[14]=-123; tv_f1[14]=-134; tv_f2[14]=-131; tv_f3[14]=-164; expected[14]=1;
        tv_f0[15]=  37; tv_f1[15]= 101; tv_f2[15]= 532; tv_f3[15]= 401; expected[15]=1;
        tv_f0[16]= -41; tv_f1[16]= -35; tv_f2[16]=  25; tv_f3[16]= 130; expected[16]=1;
        tv_f0[17]=-167; tv_f1[17]=-157; tv_f2[17]=-135; tv_f3[17]=-194; expected[17]=0;
        tv_f0[18]= -86; tv_f1[18]=-106; tv_f2[18]=-110; tv_f3[18]= -97; expected[18]=1;
        tv_f0[19]=-160; tv_f1[19]=-151; tv_f2[19]=-123; tv_f3[19]=-165; expected[19]=0;
    end

    task bus_write;
        input [4:0]  addr;
        input [31:0] data;
        begin
            reg_addr  = addr;
            reg_wdata = data;
            reg_wen   = 1'b1;
            @(posedge clk); #1;
            reg_wen   = 1'b0;
        end
    endtask

    task bus_read;
        input  [4:0]  addr;
        output [31:0] data;
        begin
            reg_addr = addr;
            reg_ren  = 1'b1;
            #1;
            data = reg_rdata;
            reg_ren  = 1'b0;
        end
    endtask

    task run_vector;
        input integer idx;
        reg [31:0] status;
        reg [31:0] result;
        integer cycles;
        begin
            bus_write(ADDR_FEATURE0, {16'd0, tv_f0[idx]});
            bus_write(ADDR_FEATURE1, {16'd0, tv_f1[idx]});
            bus_write(ADDR_FEATURE2, {16'd0, tv_f2[idx]});
            bus_write(ADDR_FEATURE3, {16'd0, tv_f3[idx]});
            bus_write(ADDR_CONTROL, 32'h00000001); // START

            // Let controller_fsm take a real clock edge to leave its
            // previous DONE/IDLE state before we start polling STATUS --
            // otherwise the first read below can catch stale status left
            // over from the previous vector's completion.
            @(posedge clk);
            #1;

            saw_busy = 1'b0;
            cycles = 0;
            bus_read(ADDR_STATUS, status);
            while (status[`STAT_BIT_DONE] !== 1'b1 && cycles < 500) begin
                if (status[`STAT_BIT_BUSY] === 1'b1)
                    saw_busy = 1'b1;
                @(posedge clk);
                cycles = cycles + 1;
                bus_read(ADDR_STATUS, status);
            end

            if (status[`STAT_BIT_DONE] !== 1'b1) begin
                fail_count = fail_count + 1;
                $display("[FAIL] vector %0d : timed out waiting for STATUS.DONE", idx);
            end else begin
                bus_read(ADDR_RESULT, result);
                if (result[`RESULT_BIT_PREDICTION] === expected[idx]) begin
                    pass_count = pass_count + 1;
                    $display("[PASS] vector %0d : prediction=%0d (expected %0d), %0d cycles, busy observed=%0d",
                              idx, result[`RESULT_BIT_PREDICTION], expected[idx], cycles, saw_busy);
                end else begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] vector %0d : prediction=%0d (expected %0d)",
                              idx, result[`RESULT_BIT_PREDICTION], expected[idx]);
                end
                if (!saw_busy) begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] vector %0d : STATUS.BUSY was never observed asserted while polling", idx);
                end
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        reg_addr = 0; reg_wdata = 0; reg_wen = 0; reg_ren = 0;

        rst = 1'b1;
        @(posedge clk); @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // Run all 20 real test vectors back-to-back, no idle gap between them
        for (i = 0; i < NUM_VECTORS; i = i + 1) begin
            run_vector(i);
        end

        // ---- summary ----
        $display("--------------------------------------------------");
        $display("accelerator_top_tb summary: %0d passed, %0d failed (out of %0d checks across %0d vectors)",
                  pass_count, fail_count, pass_count + fail_count, NUM_VECTORS);
        if (fail_count == 0)
            $display("accelerator_top_tb: ALL TESTS PASSED -- hardware matches the golden-reference Q8.8 model on all %0d real test vectors", NUM_VECTORS);
        else
            $display("accelerator_top_tb: FAILURES PRESENT");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
