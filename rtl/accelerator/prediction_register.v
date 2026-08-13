//==============================================================================
// prediction_register.v
// TinyRISC-TinyML — final classification decision latch
// HDS Section 3.7, Table 11. Implementation order #6.
// Depends on: output_layer's class-score outputs.
//
// Latches the single-bit prediction (0 = Normal, 1 = Fault) exactly once
// per inference, on latch_prediction (pulsed by controller_fsm on entry to
// S_DONE). Tie-breaking rule (HDS 3.4.9 / 3.7.2): class1_score must be
// STRICTLY greater than class0_score to declare Fault; a tie resolves to
// Normal (class 0) — the conservative, fail-safe choice.
//==============================================================================
`include "parameters.vh"

module prediction_register #(
    parameter DATA_WIDTH = `DATA_WIDTH   // 16
) (
    input  wire clk,
    input  wire rst,

    input  wire latch_prediction,  // one-cycle pulse from controller_fsm
    input  wire signed [DATA_WIDTH-1:0] class0_score,
    input  wire signed [DATA_WIDTH-1:0] class1_score,

    output reg  prediction_q       // 0 = Normal, 1 = Fault
);

    wire fault_wins;
    assign fault_wins = (class1_score > class0_score); // strict >, ties -> Normal

    always @(posedge clk) begin
        if (rst)
            prediction_q <= 1'b0;
        else if (latch_prediction)
            prediction_q <= fault_wins;
        // else: hold previous value (implicit)
    end

endmodule
