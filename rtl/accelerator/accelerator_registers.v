//==============================================================================
// accelerator_registers.v
// TinyRISC-TinyML — CPU-visible memory-mapped register file
// HDS Section 3.6, Table 10; bit map per HDS Table 4 / Chapter 2.3.
// Implementation order #8. Depends on the final register map (frozen from
// SSD/HDS) and controller_fsm's start/done/busy signals.
//
// Single-cycle read (combinational mux) / write (synchronous), no
// multi-cycle bus protocol (Master Frozen Design Decision: plain
// memory-mapped registers, no AXI/DMA/interrupts). bus_addr is a
// word-aligned byte address; only bits [4:2] are decoded (7 word offsets,
// 0x00..0x18 — HDS 3.6.2, ADDR_WIDTH implementer-defined >= 3 bits).
//==============================================================================
`include "parameters.vh"
`include "types.vh"

module accelerator_registers #(
    parameter DATA_WIDTH = `DATA_WIDTH   // 16, width of FEATURE/RESULT payload
) (
    input  wire clk,
    input  wire rst,

    // CPU bus interface (adapted from PicoRV32's native memory interface
    // by soc_top's address-range decode — see Phase 6)
    input  wire [4:0]  bus_addr,   // byte address; [4:2] decodes the 7 words
    input  wire [31:0] bus_wdata,
    input  wire        bus_wen,
    input  wire        bus_ren,
    output reg  [31:0] bus_rdata,

    // to controller_fsm
    output reg  start_pulse,      // one-cycle pulse on CONTROL.START write
    output wire soft_reset_out,   // level, reflects CONTROL.SOFT_RESET

    // to hidden_layer (via tinyml_accelerator_top wiring)
    output wire signed [DATA_WIDTH-1:0] feature0_out,
    output wire signed [DATA_WIDTH-1:0] feature1_out,
    output wire signed [DATA_WIDTH-1:0] feature2_out,
    output wire signed [DATA_WIDTH-1:0] feature3_out,

    // from controller_fsm / prediction_register
    input  wire busy_in,
    input  wire done_in,
    input  wire prediction_in
);

    reg [31:0] control_q;               // only bits [1:0] meaningful
    reg signed [DATA_WIDTH-1:0] feature0_q, feature1_q, feature2_q, feature3_q;

    wire [2:0] word_sel = bus_addr[4:2];

    assign soft_reset_out = control_q[`CTRL_BIT_SOFT_RESET];
    assign feature0_out   = feature0_q;
    assign feature1_out   = feature1_q;
    assign feature2_out   = feature2_q;
    assign feature3_out   = feature3_q;

    // ---- synchronous write path ----
    always @(posedge clk) begin
        if (rst) begin
            control_q  <= 32'd0;
            feature0_q <= {DATA_WIDTH{1'b0}};
            feature1_q <= {DATA_WIDTH{1'b0}};
            feature2_q <= {DATA_WIDTH{1'b0}};
            feature3_q <= {DATA_WIDTH{1'b0}};
            start_pulse <= 1'b0;
        end else begin
            start_pulse <= 1'b0; // default: self-clearing one-cycle pulse

            if (bus_wen) begin
                case (word_sel)
                    `REG_ADDR_CONTROL: begin
                        // bit0 START: not stored as a persistent level — it
                        // only ever produces a derived one-cycle pulse.
                        // bit1 SOFT_RESET: stored as a level (no auto-clear;
                        // software must write it back to 0).
                        control_q[`CTRL_BIT_SOFT_RESET] <= bus_wdata[`CTRL_BIT_SOFT_RESET];
                        if (bus_wdata[`CTRL_BIT_START])
                            start_pulse <= 1'b1;
                    end
                    `REG_ADDR_FEATURE0: feature0_q <= bus_wdata[DATA_WIDTH-1:0];
                    `REG_ADDR_FEATURE1: feature1_q <= bus_wdata[DATA_WIDTH-1:0];
                    `REG_ADDR_FEATURE2: feature2_q <= bus_wdata[DATA_WIDTH-1:0];
                    `REG_ADDR_FEATURE3: feature3_q <= bus_wdata[DATA_WIDTH-1:0];
                    default: ; // STATUS/RESULT are read-only; writes ignored
                endcase
            end
        end
    end

    // ---- combinational read path ----
    // STATUS/RESULT are not separately registered here — they pass through
    // combinationally from busy_in/done_in/prediction_in, which already
    // originate from registers inside controller_fsm/prediction_register
    // (HDS 3.6.3), avoiding an extra cycle of read latency.
    always @(*) begin
        bus_rdata = 32'd0;
        if (bus_ren) begin
            case (word_sel)
                `REG_ADDR_CONTROL:  bus_rdata = {30'd0, control_q[`CTRL_BIT_SOFT_RESET], 1'b0};
                `REG_ADDR_STATUS:   bus_rdata = {29'd0, 1'b0 /*ERROR, reserved*/, busy_in, done_in};
                `REG_ADDR_FEATURE0: bus_rdata = {{(32-DATA_WIDTH){1'b0}}, feature0_q};
                `REG_ADDR_FEATURE1: bus_rdata = {{(32-DATA_WIDTH){1'b0}}, feature1_q};
                `REG_ADDR_FEATURE2: bus_rdata = {{(32-DATA_WIDTH){1'b0}}, feature2_q};
                `REG_ADDR_FEATURE3: bus_rdata = {{(32-DATA_WIDTH){1'b0}}, feature3_q};
                `REG_ADDR_RESULT:   bus_rdata = {31'd0, prediction_in};
                default:            bus_rdata = 32'd0; // out-of-range: no aliasing
            endcase
        end
    end

endmodule
