//==============================================================================
// mac.v
// TinyRISC-TinyML — shared Q8.8 multiply-accumulate unit
// HDS Section 3.1, Table 5. Implementation order #1 (no dependencies).
//
// One signed Q8.8 x Q8.8 multiply per enabled cycle, renormalized back to
// Q8.8 by an arithmetic right shift of 8 (truncating, not rounding — HDS
// Section 1.8), accumulated into a 32-bit signed accumulator. acc_clear
// takes priority over en if both are asserted the same cycle (HDS 3.1.9).
//==============================================================================
`include "../common/parameters.vh"

module mac #(
    parameter DATA_WIDTH = `DATA_WIDTH,   // 16
    parameter ACC_WIDTH  = `ACC_WIDTH     // 32
) (
    input  wire                    clk,
    input  wire                    rst,        // synchronous, active-high
    input  wire                    en,         // perform one MAC step this cycle
    input  wire                    acc_clear,  // synchronously clear acc_q this cycle
    input  wire signed [DATA_WIDTH-1:0] operand_a, // feature / hidden activation
    input  wire signed [DATA_WIDTH-1:0] operand_b, // weight (from ROM)
    output wire signed [ACC_WIDTH-1:0]  acc_out    // current accumulator value
);

    reg signed [ACC_WIDTH-1:0] acc_q;

    // Q8.8 x Q8.8 -> Q16.16 (32-bit) signed product, renormalized to Q8.8
    // scale by an arithmetic (sign-preserving) right shift of 8, per
    // HDS Section 3.1.6/3.1.8. Held at full 32-bit width for accumulation
    // headroom (HDS Section 1.7, Overflow Strategy item 2).
    wire signed [2*DATA_WIDTH-1:0] product;
    wire signed [ACC_WIDTH-1:0]    renormalized;

    assign product      = operand_a * operand_b;
    assign renormalized = product >>> `FRAC_BITS;

    always @(posedge clk) begin
        if (rst)
            acc_q <= {ACC_WIDTH{1'b0}};
        else if (acc_clear)
            acc_q <= {ACC_WIDTH{1'b0}};
        else if (en)
            acc_q <= acc_q + renormalized;
        // else: hold (implicit)
    end

    assign acc_out = acc_q;

endmodule
