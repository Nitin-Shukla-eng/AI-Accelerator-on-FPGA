//==============================================================================
// relu.v
// TinyRISC-TinyML — combinational ReLU activation
// HDS Section 3.2, Table 6. Implementation order #2 (no dependencies).
//
// f(x) = max(0, x). Zero-cycle, pure combinational: a single sign-bit test.
// Intended to feed directly into a register in the calling module (HDS
// Section 3.2.5) so the overall pipeline stage still has one registered
// boundary — relu.v itself contains no registers.
//==============================================================================
`include "parameters.vh"

module relu #(
    parameter DATA_WIDTH = `DATA_WIDTH   // 16
) (
    input  wire signed [DATA_WIDTH-1:0] data_in,
    output wire signed [DATA_WIDTH-1:0] data_out
);

    // data_in[MSB] is the sign bit for a two's-complement signed value.
    assign data_out = data_in[DATA_WIDTH-1] ? {DATA_WIDTH{1'b0}} : data_in;

endmodule
