//==============================================================================
// output_layer.v
// TinyRISC-TinyML — output-layer forward pass (8 -> 2, no activation)
// HDS Section 3.4, Table 8, Figure 8. Implementation order #5.
// Depends on: mac (reused), output_weight_rom, output_bias_rom.
//
// For each of the 2 output neurons: clear the shared mac accumulator, MAC
// the 8 hidden activations against that neuron's weight row, add the bias,
// saturate to Q8.8 — no ReLU at this stage (HDS 3.4.1, standard classifier
// convention: raw scores compared directly). 10 cycles/neuron (CLEAR 1 +
// MAC 8 + BIAS_CAPTURE 1), per HDS Section 3.4.6, with bias-add, saturation
// and score-register capture folded into a single cycle exactly as
// specified there.
//
// Coding style: two-block FSM (synchronous state/counter registers +
// combinational next-state/output logic), per HDS RTL coding standard.
//==============================================================================
`include "parameters.vh"
`include "defines.vh"

module output_layer #(
    parameter NUM_HIDDEN  = `NUM_HIDDEN,   // 8
    parameter NUM_CLASSES = `NUM_CLASSES,  // 2
    parameter DATA_WIDTH  = `DATA_WIDTH    // 16
) (
    input  wire clk,
    input  wire rst,

    input  wire start_output,   // pulsed by controller_fsm after hidden_done

    input  wire signed [NUM_HIDDEN*DATA_WIDTH-1:0] hidden_act_in,

    input  wire signed [DATA_WIDTH-1:0] output_w_dout,
    input  wire signed [DATA_WIDTH-1:0] output_b_dout,
    output wire [`OUTPUT_W_ADDR_WIDTH-1:0] output_w_addr,
    output wire [`OUTPUT_B_ADDR_WIDTH-1:0] output_b_addr,

    output reg  output_done,    // pulsed one cycle when both class scores valid
    output reg  signed [DATA_WIDTH-1:0] class0_score,  // Normal-class raw score
    output reg  signed [DATA_WIDTH-1:0] class1_score   // Fault-class raw score
);

    // ---- state/counter registers ----
    reg [1:0] ol_state_q2, ol_state_d;   // uses OL_* encoding (defines.vh)
    reg       class_idx_q, class_idx_d;   // 0..1
    reg [2:0] hidden_idx_q, hidden_idx_d; // 0..7

    // ---- combinational output/next-state logic ----
    reg mac_en, mac_acc_clear;
    reg output_done_d;
    reg capture_pulse; // combinational: OL_BIAS state, asserted this cycle

    wire signed [DATA_WIDTH-1:0] hidden_act_muxed;
    assign hidden_act_muxed = hidden_act_in[hidden_idx_q*DATA_WIDTH +: DATA_WIDTH];

    wire signed [`ACC_WIDTH-1:0] mac_acc_out;
    mac u_mac (
        .clk       (clk),
        .rst       (rst),
        .en        (mac_en),
        .acc_clear (mac_acc_clear),
        .operand_a (hidden_act_muxed),
        .operand_b (output_w_dout),
        .acc_out   (mac_acc_out)
    );

    // ROM address generation (HDS Figure 9: class-major, {class_idx, hidden_idx})
    assign output_w_addr = {class_idx_q, hidden_idx_q};
    assign output_b_addr = class_idx_q;

    // Bias add + saturate — no ReLU at the output stage (HDS 3.4.5/3.4.8)
    wire signed [`ACC_WIDTH-1:0] bias_add_wide;
    assign bias_add_wide = mac_acc_out + {{16{output_b_dout[DATA_WIDTH-1]}}, output_b_dout};
    wire signed [DATA_WIDTH-1:0] bias_saturated;
    assign bias_saturated = `SATURATE_Q8_8(bias_add_wide);

    // ---- combinational next-state / control block ----
    always @(*) begin
        // defaults
        ol_state_d    = ol_state_q2;
        class_idx_d   = class_idx_q;
        hidden_idx_d  = hidden_idx_q;
        mac_en        = 1'b0;
        mac_acc_clear = 1'b0;
        output_done_d = 1'b0;
        capture_pulse = 1'b0;

        case (ol_state_q2)
            `OL_IDLE: begin
                if (start_output) begin
                    class_idx_d = 1'b0;
                    ol_state_d  = `OL_CLEAR;
                end
            end

            `OL_CLEAR: begin
                mac_acc_clear = 1'b1;
                hidden_idx_d  = 3'd0;
                ol_state_d    = `OL_MAC;
            end

            `OL_MAC: begin
                mac_en = 1'b1;
                if (hidden_idx_q == NUM_HIDDEN-1) begin
                    ol_state_d = `OL_BIAS;
                end else begin
                    hidden_idx_d = hidden_idx_q + 1'b1;
                end
            end

            `OL_BIAS: begin
                // mac_acc_out reflects the 8th (final) MAC step, latched at
                // the edge that moved us from OL_MAC into OL_BIAS.
                capture_pulse = 1'b1;
                if (class_idx_q == NUM_CLASSES-1) begin
                    output_done_d = 1'b1;
                    ol_state_d    = `OL_IDLE;
                end else begin
                    class_idx_d = class_idx_q + 1'b1;
                    ol_state_d  = `OL_CLEAR;
                end
            end

            default: ol_state_d = `OL_IDLE;
        endcase
    end

    // ---- synchronous state update ----
    always @(posedge clk) begin
        if (rst) begin
            ol_state_q2  <= `OL_IDLE;
            class_idx_q  <= 1'b0;
            hidden_idx_q <= 3'd0;
            output_done  <= 1'b0;
            class0_score <= {DATA_WIDTH{1'b0}};
            class1_score <= {DATA_WIDTH{1'b0}};
        end else begin
            ol_state_q2  <= ol_state_d;
            class_idx_q  <= class_idx_d;
            hidden_idx_q <= hidden_idx_d;
            output_done  <= output_done_d;

            if (capture_pulse) begin
                if (class_idx_q == 1'b0)
                    class0_score <= bias_saturated;
                else
                    class1_score <= bias_saturated;
            end
        end
    end

endmodule
