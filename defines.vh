//==============================================================================
// defines.vh
// TinyRISC-TinyML — common `define macros
//
// Per HDS Table 1 (Signal Naming Rules) and Chapter 3 module specs.
// Included by every RTL module that needs FSM state encodings or the
// shared Q8.8 saturation macro. Plain Verilog-2001 (no SystemVerilog),
// per HDS coding standard #12 (no #delay in synthesizable RTL) and the
// Hardware Language decision (Verilog HDL).
//==============================================================================
`ifndef TINYML_DEFINES_VH
`define TINYML_DEFINES_VH

//------------------------------------------------------------------------------
// controller_fsm top-level state encoding (HDS Table 9 / Figure 3)
// Binary encoding, 3 bits — frozen implementation choice (HDS 3.5.4 leaves
// one-hot vs. binary to the implementer; binary chosen here to keep the
// state register small; documented here so it is not re-decided per module).
//------------------------------------------------------------------------------
`define S_IDLE   3'd0
`define S_LOAD   3'd1
`define S_HIDDEN 3'd2
`define S_OUTPUT 3'd3
`define S_DONE   3'd4

//------------------------------------------------------------------------------
// hidden_layer local micro-sequencer state encoding (HDS 3.3.7 — documented
// as local bookkeeping counters, not an architectural FSM, but implemented
// here as an explicit small state register for clarity/verifiability).
// 7 cycles/neuron: CLEAR(1) + MAC(4, one per feature) + BIAS(1) + STORE(1).
//------------------------------------------------------------------------------
`define HL_IDLE  3'd0
`define HL_CLEAR 3'd1
`define HL_MAC   3'd2
`define HL_BIAS  3'd3
`define HL_STORE 3'd4

//------------------------------------------------------------------------------
// output_layer local micro-sequencer state encoding (HDS 3.4.7).
// 10 cycles/neuron: CLEAR(1) + MAC(8, one per hidden activation) +
// BIAS_CAPTURE(1) — bias-add, saturation and score-register capture folded
// into a single cycle, exactly as specified in HDS 3.4.6.
//------------------------------------------------------------------------------
`define OL_IDLE  2'd0
`define OL_CLEAR 2'd1
`define OL_MAC   2'd2
`define OL_BIAS  2'd3

//------------------------------------------------------------------------------
// Q8.8 saturation macro (HDS Section 1.7, Overflow Strategy, item 3).
// WIDE must be a 32-bit *signed* expression already aligned to Q8.8 scale
// (i.e. accumulator-plus-bias). Clamps to the representable 16-bit signed
// Q8.8 range [16'h8000 .. 16'h7FFF] instead of wrapping.
//------------------------------------------------------------------------------
`define SATURATE_Q8_8(WIDE) \
    (($signed(WIDE) > 32'sd32767)  ? 16'sh7FFF : \
     ($signed(WIDE) < -32'sd32768) ? 16'sh8000 : \
                                      WIDE[15:0])

`endif // TINYML_DEFINES_VH
