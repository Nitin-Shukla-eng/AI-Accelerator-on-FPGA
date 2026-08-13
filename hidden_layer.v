//==============================================================================
// hidden_layer.v
// TinyRISC-TinyML — hidden-layer forward pass (4 -> 8, ReLU)
// HDS Section 3.3, Table 7, Figure 7. Implementation order #4.
// Depends on: mac, relu, hidden_weight_rom, hidden_bias_rom.
//
// For each of the 8 hidden neurons: clear the shared mac accumulator,
// MAC the 4 features against that neuron's weight row, add the bias,
// saturate to Q8.8, apply ReLU, and store into the internal Hidden
// Activation Memory. 7 cycles/neuron (CLEAR 1 + MAC 4 + BIAS 1 + STORE 1),
// per HDS Section 3.3.6's unoptimized/straightforward timing baseline — the
// bias-fold micro-optimization HDS explicitly permits is deferred (not
// applied) here so behavior is easiest to verify bit-exactly against the
// Python reference first.
//
// Coding style: two-block FSM (synchronous state/counter registers +
// combinational next-state/output logic), per HDS RTL coding standard.
//==============================================================================
`include "parameters.vh"
`include "defines.vh"

module hidden_layer #(
    parameter NUM_FEATURES = `NUM_FEATURES,  // 4
    parameter NUM_HIDDEN   = `NUM_HIDDEN,    // 8
    parameter DATA_WIDTH   = `DATA_WIDTH     // 16
) (
    input  wire clk,
    input  wire rst,

    input  wire start_hidden,   // pulsed by controller_fsm to kick off computation

    input  wire signed [DATA_WIDTH-1:0] feature0,
    input  wire signed [DATA_WIDTH-1:0] feature1,
    input  wire signed [DATA_WIDTH-1:0] feature2,
    input  wire signed [DATA_WIDTH-1:0] feature3,

    input  wire signed [DATA_WIDTH-1:0] hidden_w_dout,
    input  wire signed [DATA_WIDTH-1:0] hidden_b_dout,
    output wire [`HIDDEN_W_ADDR_WIDTH-1:0] hidden_w_addr,
    output wire [`HIDDEN_B_ADDR_WIDTH-1:0] hidden_b_addr,

    output reg  hidden_done,    // pulsed one cycle when all 8 activations stored

    // Hidden Activation Memory, exposed flattened to output_layer
    // (8 x 16-bit signed, neuron 0 in the low slice).
    output wire signed [NUM_HIDDEN*DATA_WIDTH-1:0] hidden_act_out
);

    // ---- state/counter registers ----
    reg [2:0] hl_state_q, hl_state_d;
    reg [2:0] neuron_idx_q, neuron_idx_d;   // 0..7
    reg [1:0] feature_idx_q, feature_idx_d; // 0..3
    reg signed [DATA_WIDTH-1:0] bias_add_q; // saturated, pre-ReLU, pipeline reg

    // Hidden Activation Memory: 8-entry x 16-bit register array (HDS 3.3.4)
    reg signed [DATA_WIDTH-1:0] hidden_act_mem [0:NUM_HIDDEN-1];

    // ---- combinational output/next-state logic ----
    reg mac_en, mac_acc_clear;
    reg hidden_done_d;
    reg store_pulse; // combinational: HL_STORE state, asserted this cycle

    reg signed [DATA_WIDTH-1:0] feature_muxed;
    always @(*) begin
        case (feature_idx_q)
            2'd0: feature_muxed = feature0;
            2'd1: feature_muxed = feature1;
            2'd2: feature_muxed = feature2;
            default: feature_muxed = feature3;
        endcase
    end

    wire signed [`ACC_WIDTH-1:0] mac_acc_out;
    mac u_mac (
        .clk       (clk),
        .rst       (rst),
        .en        (mac_en),
        .acc_clear (mac_acc_clear),
        .operand_a (feature_muxed),
        .operand_b (hidden_w_dout),
        .acc_out   (mac_acc_out)
    );

    // ROM address generation (HDS Figure 9: neuron-major, {neuron_idx, feature_idx})
    assign hidden_w_addr = {neuron_idx_q, feature_idx_q};
    assign hidden_b_addr = neuron_idx_q;

    // Bias add + saturate (HDS Section 1.7 item 3 / 3.3.5)
    wire signed [`ACC_WIDTH-1:0] bias_add_wide;
    assign bias_add_wide = mac_acc_out + {{16{hidden_b_dout[DATA_WIDTH-1]}}, hidden_b_dout};
    wire signed [DATA_WIDTH-1:0] bias_saturated;
    assign bias_saturated = `SATURATE_Q8_8(bias_add_wide);

    // ReLU (zero-cycle, combinational — HDS 3.2)
    wire signed [DATA_WIDTH-1:0] relu_out;
    relu u_relu (
        .data_in  (bias_add_q),
        .data_out (relu_out)
    );

    // ---- combinational next-state / control block ----
    always @(*) begin
        // defaults
        hl_state_d    = hl_state_q;
        neuron_idx_d  = neuron_idx_q;
        feature_idx_d = feature_idx_q;
        mac_en        = 1'b0;
        mac_acc_clear = 1'b0;
        hidden_done_d = 1'b0;
        store_pulse   = 1'b0;

        case (hl_state_q)
            `HL_IDLE: begin
                if (start_hidden) begin
                    neuron_idx_d = 3'd0;
                    hl_state_d   = `HL_CLEAR;
                end
            end

            `HL_CLEAR: begin
                mac_acc_clear = 1'b1;
                feature_idx_d = 2'd0;
                hl_state_d    = `HL_MAC;
            end

            `HL_MAC: begin
                mac_en = 1'b1;
                if (feature_idx_q == NUM_FEATURES-1) begin
                    hl_state_d = `HL_BIAS;
                end else begin
                    feature_idx_d = feature_idx_q + 1'b1;
                end
            end

            `HL_BIAS: begin
                // mac_acc_out reflects the 4th (final) MAC step, latched at
                // the edge that moved us from HL_MAC into HL_BIAS (HDS 3.1.7).
                hl_state_d = `HL_STORE;
            end

            `HL_STORE: begin
                store_pulse = 1'b1;
                if (neuron_idx_q == NUM_HIDDEN-1) begin
                    hidden_done_d = 1'b1;
                    hl_state_d    = `HL_IDLE;
                end else begin
                    neuron_idx_d = neuron_idx_q + 1'b1;
                    hl_state_d   = `HL_CLEAR;
                end
            end

            default: hl_state_d = `HL_IDLE;
        endcase
    end

    // ---- synchronous state update ----
    integer k;
    always @(posedge clk) begin
        if (rst) begin
            hl_state_q    <= `HL_IDLE;
            neuron_idx_q  <= 3'd0;
            feature_idx_q <= 2'd0;
            bias_add_q    <= {DATA_WIDTH{1'b0}};
            hidden_done   <= 1'b0;
            for (k = 0; k < NUM_HIDDEN; k = k + 1)
                hidden_act_mem[k] <= {DATA_WIDTH{1'b0}};
        end else begin
            hl_state_q    <= hl_state_d;
            neuron_idx_q  <= neuron_idx_d;
            feature_idx_q <= feature_idx_d;
            hidden_done   <= hidden_done_d;

            if (hl_state_q == `HL_BIAS)
                bias_add_q <= bias_saturated;

            if (store_pulse)
                hidden_act_mem[neuron_idx_q] <= relu_out;
        end
    end

    // Flatten the activation memory for output_layer
    genvar g;
    generate
        for (g = 0; g < NUM_HIDDEN; g = g + 1) begin : FLATTEN
            assign hidden_act_out[(g+1)*DATA_WIDTH-1 -: DATA_WIDTH] = hidden_act_mem[g];
        end
    endgenerate

endmodule
