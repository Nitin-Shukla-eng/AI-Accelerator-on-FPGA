//==============================================================================
// tinyml_accelerator_top.v
// TinyRISC-TinyML — accelerator top-level integration
// HDS Chapter 2.2 (interface), Chapter 10 (Figure 2 hierarchy),
// Implementation order #9. Integrates modules #4-8 above:
//   accelerator_registers, controller_fsm, hidden_layer, output_layer,
//   prediction_register, and the four generated ROMs.
//
// This is the accelerator's addressable unit as seen from soc_top (Phase 6):
// reg_addr/reg_wdata/reg_wen/reg_rdata/reg_ren in, nothing else externally
// visible — everything else is internal wiring per Figure 2.
//==============================================================================
`include "parameters.vh"

module tinyml_accelerator_top #(
    parameter DATA_WIDTH = `DATA_WIDTH
) (
    input  wire        clk,
    input  wire        rst,

    input  wire [4:0]  reg_addr,   // byte address, [4:2] decodes 7 words
    input  wire [31:0] reg_wdata,
    input  wire        reg_wen,
    input  wire        reg_ren,
    output wire [31:0] reg_rdata
);

    // ---- accelerator_registers <-> controller_fsm / hidden_layer wiring ----
    wire start_pulse;
    wire soft_reset;
    wire signed [DATA_WIDTH-1:0] feature0, feature1, feature2, feature3;
    wire busy, done, prediction;

    accelerator_registers u_regs (
        .clk            (clk),
        .rst            (rst),
        .bus_addr       (reg_addr),
        .bus_wdata      (reg_wdata),
        .bus_wen        (reg_wen),
        .bus_ren        (reg_ren),
        .bus_rdata      (reg_rdata),
        .start_pulse    (start_pulse),
        .soft_reset_out (soft_reset),
        .feature0_out   (feature0),
        .feature1_out   (feature1),
        .feature2_out   (feature2),
        .feature3_out   (feature3),
        .busy_in        (busy),
        .done_in        (done),
        .prediction_in  (prediction)
    );

    // ---- controller_fsm <-> hidden_layer / output_layer handshake ----
    wire start_hidden, start_output;
    wire hidden_done, output_done;
    wire latch_prediction;

    controller_fsm u_fsm (
        .clk               (clk),
        .rst               (rst),
        .start_bit         (start_pulse),
        .soft_reset_bit    (soft_reset),
        .hidden_done       (hidden_done),
        .output_done       (output_done),
        .start_hidden      (start_hidden),
        .start_output      (start_output),
        .busy              (busy),
        .done              (done),
        .latch_prediction  (latch_prediction)
    );

    // ---- hidden_layer <-> hidden ROMs ----
    wire [`HIDDEN_W_ADDR_WIDTH-1:0] hidden_w_addr;
    wire [`HIDDEN_B_ADDR_WIDTH-1:0] hidden_b_addr;
    wire signed [DATA_WIDTH-1:0]    hidden_w_dout, hidden_b_dout;
    wire signed [`NUM_HIDDEN*DATA_WIDTH-1:0] hidden_act;

    hidden_weight_rom u_hidden_w_rom (
        .addr (hidden_w_addr),
        .dout (hidden_w_dout)
    );

    hidden_bias_rom u_hidden_b_rom (
        .addr (hidden_b_addr),
        .dout (hidden_b_dout)
    );

    hidden_layer u_hidden_layer (
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
        .hidden_act_out (hidden_act)
    );

    // ---- output_layer <-> output ROMs ----
    wire [`OUTPUT_W_ADDR_WIDTH-1:0] output_w_addr;
    wire [`OUTPUT_B_ADDR_WIDTH-1:0] output_b_addr;
    wire signed [DATA_WIDTH-1:0]    output_w_dout, output_b_dout;
    wire signed [DATA_WIDTH-1:0]    class0_score, class1_score;

    output_weight_rom u_output_w_rom (
        .addr (output_w_addr),
        .dout (output_w_dout)
    );

    output_bias_rom u_output_b_rom (
        .addr (output_b_addr),
        .dout (output_b_dout)
    );

    output_layer u_output_layer (
        .clk           (clk),
        .rst           (rst),
        .start_output  (start_output),
        .hidden_act_in (hidden_act),
        .output_w_dout (output_w_dout),
        .output_b_dout (output_b_dout),
        .output_w_addr (output_w_addr),
        .output_b_addr (output_b_addr),
        .output_done   (output_done),
        .class0_score  (class0_score),
        .class1_score  (class1_score)
    );

    // ---- prediction_register ----
    prediction_register u_prediction_register (
        .clk              (clk),
        .rst              (rst),
        .latch_prediction (latch_prediction),
        .class0_score     (class0_score),
        .class1_score     (class1_score),
        .prediction_q     (prediction)
    );

endmodule
