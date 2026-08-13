//==============================================================================
// types.vh
// TinyRISC-TinyML — register bit-field positions
//
// Plain Verilog-2001 has no typedef/struct, so "types" here means the named
// bit positions within the CONTROL/STATUS/RESULT registers (HDS Table 4 —
// Detailed Register Bit Map), kept in one place so accelerator_registers.v
// and any testbench/driver code agree on bit numbering by construction
// rather than by convention.
//==============================================================================
`ifndef TINYML_TYPES_VH
`define TINYML_TYPES_VH

// CONTROL register (0x00)
`define CTRL_BIT_START       0   // W, self-clearing internally
`define CTRL_BIT_SOFT_RESET  1   // W, level; software writes 0 back after use

// STATUS register (0x04)
`define STAT_BIT_DONE        0   // R
`define STAT_BIT_BUSY        1   // R
`define STAT_BIT_ERROR       2   // R, reserved, always 0 in current release

// RESULT register (0x18)
`define RESULT_BIT_PREDICTION 0  // R, 0 = Normal, 1 = Fault, valid iff STATUS.DONE

`endif // TINYML_TYPES_VH
