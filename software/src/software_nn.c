/*==============================================================================
 * software_nn.c
 * TinyRISC-TinyML -- Version 1 (pure software) forward pass implementation
 *
 * CRITICAL: this arithmetic must match rtl/math/mac.v EXACTLY -- each
 * product is renormalized (right-shifted by FRAC_BITS) INDIVIDUALLY,
 * before being accumulated, rather than summing raw Q16.16 products and
 * shifting once at the end. These are NOT equivalent (per-term truncation
 * loses up to 1 LSB per term versus a single shift after the sum). This
 * is the exact same fix applied to python/quantize.py's quantize_forward()
 * during Phase 3/4 -- see PHASE3_NOTES.md. If this ever drifts from
 * mac.v's arithmetic, Version 1 and Version 2 can predict different
 * classes on the same input near a decision boundary, which would fail
 * AC-01 (all three of float/software/hardware must agree) without any
 * bug in the RTL at all.
 *
 * Right-shift-of-a-negative-signed-int is implementation-defined by the
 * C standard, but is implemented as an arithmetic (sign-propagating)
 * shift by every mainstream compiler and architecture, including the
 * RISC-V GCC toolchain this project targets -- this matches Verilog's
 * `>>>` on a two's-complement signed value exactly. If this is ever
 * built with an unusual compiler, verify this assumption still holds.
 *============================================================================*/
#include "software_nn.h"

#define FRAC_BITS 8

/* Saturate a wider accumulator value into the signed 16-bit Q8.8 range,
 * matching rtl/common/defines.vh's SATURATE_Q8_8 macro exactly. */
static int16_t saturate_q8_8(int32_t value) {
    if (value > 32767)
        return 32767;
    if (value < -32768)
        return -32768;
    return (int16_t)value;
}

static int16_t relu_q8_8(int16_t value) {
    return (value < 0) ? 0 : value;
}

uint8_t software_nn_infer(const int16_t features[NUM_INPUTS]) {
    int16_t hidden_act[NUM_HIDDEN];
    int16_t class_score[NUM_OUTPUTS];

    /* ---- hidden layer: NUM_HIDDEN neurons, ReLU activation ---- */
    for (int neuron = 0; neuron < NUM_HIDDEN; neuron++) {
        int32_t acc = 0;
        for (int in_idx = 0; in_idx < NUM_INPUTS; in_idx++) {
            int16_t w = hidden_weights[neuron * NUM_INPUTS + in_idx];
            int32_t product = (int32_t)features[in_idx] * (int32_t)w;
            int32_t renormalized = product >> FRAC_BITS; /* per-term shift, matches mac.v */
            acc += renormalized;
        }
        acc += hidden_biases[neuron];
        hidden_act[neuron] = relu_q8_8(saturate_q8_8(acc));
    }

    /* ---- output layer: NUM_OUTPUTS classes, NO activation ---- */
    for (int class_idx = 0; class_idx < NUM_OUTPUTS; class_idx++) {
        int32_t acc = 0;
        for (int hid_idx = 0; hid_idx < NUM_HIDDEN; hid_idx++) {
            int16_t w = output_weights[class_idx * NUM_HIDDEN + hid_idx];
            int32_t product = (int32_t)hidden_act[hid_idx] * (int32_t)w;
            int32_t renormalized = product >> FRAC_BITS;
            acc += renormalized;
        }
        acc += output_biases[class_idx];
        class_score[class_idx] = saturate_q8_8(acc);
    }

    /* Strict > required for Fault, tie resolves to Normal -- matches
     * prediction_register.v's comparator exactly. */
    return (class_score[1] > class_score[0]) ? 1 : 0;
}
