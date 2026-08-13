//==============================================================================
// parameters.vh
// TinyRISC-TinyML — global parameters
//
// Values are the Master Frozen Design Decisions (HDS Chapter 12 / SSD
// Chapter 5): 4->8->2 topology, Q8.8 arithmetic everywhere. These are
// `define'd (not Verilog `parameter`s) so every module can `include this
// file and reference the same constants without re-declaring/re-passing
// them through every port list. Per-module `parameter` declarations in the
// individual RTL files default to these same values so each module stays
// independently instantiable/overridable per HDS Table 1 convention
// (Parameter: ALL_CAPS_WITH_UNDERSCORES).
//==============================================================================
`ifndef TINYML_PARAMETERS_VH
`define TINYML_PARAMETERS_VH

// Q8.8 fixed-point format (HDS Table 3)
`define DATA_WIDTH   16   // total width of one Q8.8 operand
`define FRAC_BITS    8    // fractional bits
`define ACC_WIDTH     32   // mac accumulator width

// Network topology (4 -> 8 -> 2), frozen per Master Frozen Design Decision #8
`define NUM_FEATURES  4    // input feature count (RMS, Peak, Kurtosis, Crest Factor)
`define NUM_HIDDEN    8    // hidden neuron count
`define NUM_CLASSES   2    // output neuron count (Normal, Fault)

// ROM address widths (HDS Table 12)
`define HIDDEN_W_ADDR_WIDTH 5  // 32 entries = 4 features x 8 neurons
`define HIDDEN_B_ADDR_WIDTH 3  // 8 entries
`define OUTPUT_W_ADDR_WIDTH 4  // 16 entries = 8 hidden x 2 classes
`define OUTPUT_B_ADDR_WIDTH 1  // 2 entries

// CPU-visible register block (HDS Table 4 / SSD Register Description)
`define REG_ADDR_CONTROL  3'b000  // 0x00
`define REG_ADDR_STATUS   3'b001  // 0x04
`define REG_ADDR_FEATURE0 3'b010  // 0x08
`define REG_ADDR_FEATURE1 3'b011  // 0x0C
`define REG_ADDR_FEATURE2 3'b100  // 0x10
`define REG_ADDR_FEATURE3 3'b101  // 0x14
`define REG_ADDR_RESULT   3'b110  // 0x18

`endif // TINYML_PARAMETERS_VH
