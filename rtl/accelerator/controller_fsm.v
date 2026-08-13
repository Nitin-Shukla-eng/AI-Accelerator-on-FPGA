//==============================================================================
// controller_fsm.v
// TinyRISC-TinyML — top-level accelerator sequencer
// HDS Section 3.5, Table 9, Figure 3. Implementation order #7.
// Depends only on the start/done handshake signals of hidden_layer /
// output_layer (interfaces, not internals).
//
// States: S_IDLE -> S_LOAD -> S_HIDDEN -> S_OUTPUT -> S_DONE -> (S_LOAD on
// next START, or S_IDLE). SOFT_RESET returns to S_IDLE from any state
// within one cycle. Sole authoritative FSM state register for the
// accelerator; performs no arithmetic of its own.
//
// Coding style: two-block FSM (synchronous state register + combinational
// next-state/output logic), per HDS RTL coding standard.
//==============================================================================
`include "defines.vh"

module controller_fsm (
    input  wire clk,
    input  wire rst,

    input  wire start_bit,        // CONTROL.START one-cycle pulse
    input  wire soft_reset_bit,   // CONTROL.SOFT_RESET (level)

    input  wire hidden_done,      // from hidden_layer
    input  wire output_done,      // from output_layer

    output reg  start_hidden,     // to hidden_layer
    output reg  start_output,     // to output_layer

    output reg  busy,             // to STATUS.BUSY
    output reg  done,             // to STATUS.DONE
    output reg  latch_prediction  // to prediction_register, pulsed entering S_DONE
);

    reg [2:0] state_q, state_d;

    // ---- combinational next-state / output logic ----
    always @(*) begin
        // defaults
        state_d          = state_q;
        start_hidden      = 1'b0;
        start_output      = 1'b0;
        busy              = 1'b0;
        done              = 1'b0;
        latch_prediction  = 1'b0;

        case (state_q)
            `S_IDLE: begin
                busy = 1'b0;
                done = 1'b0;
                if (start_bit)
                    state_d = `S_LOAD;
            end

            `S_LOAD: begin
                busy    = 1'b1;
                state_d = `S_HIDDEN; // unconditional, one cycle
            end

            `S_HIDDEN: begin
                busy = 1'b1;
                // Held high for the whole S_HIDDEN dwell EXCEPT the cycle
                // hidden_done is observed: hidden_layer's own local state
                // returns to HL_IDLE that same cycle, and would otherwise
                // see start_hidden still asserted and immediately restart
                // (this FSM only advances to S_OUTPUT on the *next* edge).
                start_hidden = ~hidden_done;
                if (hidden_done)
                    state_d = `S_OUTPUT;
            end

            `S_OUTPUT: begin
                busy = 1'b1;
                // Same rationale as start_hidden above.
                start_output = ~output_done;
                if (output_done)
                    state_d = `S_DONE;
            end

            `S_DONE: begin
                busy             = 1'b0;
                done             = 1'b1;
                latch_prediction = 1'b0; // pulsed only on the *entry* cycle (below)
                if (start_bit)
                    state_d = `S_LOAD;  // back-to-back inference, no S_IDLE detour
            end

            default: state_d = `S_IDLE;
        endcase

        // latch_prediction: exactly one cycle, on the S_OUTPUT -> S_DONE transition
        if (state_q == `S_OUTPUT && output_done)
            latch_prediction = 1'b1;

        // SOFT_RESET overrides from any state
        if (soft_reset_bit) begin
            state_d          = `S_IDLE;
            start_hidden      = 1'b0;
            start_output      = 1'b0;
            latch_prediction  = 1'b0;
        end
    end

    // ---- synchronous state register ----
    always @(posedge clk) begin
        if (rst)
            state_q <= `S_IDLE;
        else
            state_q <= state_d;
    end

endmodule
