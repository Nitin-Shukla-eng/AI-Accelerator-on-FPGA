/*==============================================================================
 * software_nn.h
 * TinyRISC-TinyML -- Version 1 (pure software) forward pass interface
 *
 * Runs the identical 4->8->2 Q8.8 forward pass the hardware accelerator
 * runs, entirely in C, using generated/software/weights.h (the same
 * weight file the RTL ROMs were generated from -- see export_model.py).
 * This is the "before" side of the Version 1 vs. Version 2 comparison.
 *============================================================================*/
#ifndef SOFTWARE_NN_H
#define SOFTWARE_NN_H

#include <stdint.h>
#include "weights.h" /* defines NUM_INPUTS, NUM_HIDDEN, NUM_OUTPUTS */

/*------------------------------------------------------------------------
 * software_nn_infer
 *
 * features: array of NUM_INPUTS signed Q8.8 int16 values, in the same
 *           FEATURE0..FEATURE3 order (RMS, Peak, Kurtosis, Crest Factor)
 *           used everywhere else in the project.
 *
 * Returns: predicted class, 0 = Normal, 1 = Fault -- computed with the
 *          exact same tie-break rule as prediction_register.v (strict
 *          class1 > class0 required for Fault; a tie resolves to Normal).
 *----------------------------------------------------------------------*/
uint8_t software_nn_infer(const int16_t features[NUM_INPUTS]);

#endif /* SOFTWARE_NN_H */
