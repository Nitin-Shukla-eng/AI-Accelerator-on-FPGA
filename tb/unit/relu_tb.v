//==============================================================================
// relu_tb.v
// Self-checking testbench for rtl/math/relu.v
// HDS Section 3.2 / VIS unit-test matrix, item 2 (build order: second, no
// dependencies).
//
// relu.v is purely combinational (f(x) = max(0, x), single sign-bit mux),
// so this testbench doesn't need a clock -- it just sweeps inputs and
// checks data_out combinationally after each assignment.
//
// Covers:
//   T1 - positive value passes through unchanged
//   T2 - negative value is zeroed
//   T3 - zero maps to zero
//   T4 - largest positive Q8.8 value (16'sh7FFF) passes through unchanged
//   T5 - most negative Q8.8 value (16'sh8000) is zeroed
//   T6 - smallest-magnitude negative value (-1, 16'shFFFF) is zeroed
//   T7 - smallest-magnitude positive value (+1) passes through unchanged
//
// Run:
//   iverilog -o relu_tb.vvp -I ../../rtl/common relu_tb.v ../../rtl/math/relu.v
//   vvp relu_tb.vvp
//==============================================================================
`timescale 1ns / 1ps
`include "../../rtl/common/parameters.vh"

module relu_tb;

    reg  signed [`DATA_WIDTH-1:0] data_in;
    wire signed [`DATA_WIDTH-1:0] data_out;

    integer pass_count, fail_count;

    relu dut (
        .data_in  (data_in),
        .data_out (data_out)
    );

    task check;
        input [255:0] name;
        input signed [`DATA_WIDTH-1:0] expected;
        begin
            #1; // let combinational logic settle
            if (data_out === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : data_in=%0d data_out=%0d (expected %0d)",
                          name, data_in, data_out, expected);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : data_in=%0d data_out=%0d (expected %0d)",
                          name, data_in, data_out, expected);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        // T1 - ordinary positive value, e.g. 3.5 in Q8.8 = 896
        data_in = 16'sd896;
        check("T1 positive passthrough (3.5)", 16'sd896);

        // T2 - ordinary negative value, e.g. -3.5 in Q8.8 = -896
        data_in = -16'sd896;
        check("T2 negative zeroed (-3.5)", 16'sd0);

        // T3 - zero
        data_in = 16'sd0;
        check("T3 zero maps to zero", 16'sd0);

        // T4 - largest representable positive Q8.8 value
        data_in = 16'sh7FFF;
        check("T4 max positive passthrough", 16'sh7FFF);

        // T5 - most negative representable Q8.8 value
        data_in = 16'sh8000;
        check("T5 min negative zeroed", 16'sd0);

        // T6 - smallest-magnitude negative value (-1 LSB)
        data_in = -16'sd1;
        check("T6 smallest negative zeroed (-1)", 16'sd0);

        // T7 - smallest-magnitude positive value (+1 LSB)
        data_in = 16'sd1;
        check("T7 smallest positive passthrough (+1)", 16'sd1);

        // ---- summary ----
        $display("--------------------------------------------------");
        $display("relu_tb summary: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("relu_tb: ALL TESTS PASSED");
        else
            $display("relu_tb: FAILURES PRESENT");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
