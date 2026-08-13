/*==============================================================================
 * accelerator_driver.h
 * TinyRISC-TinyML -- Version 2 (hardware accelerator) driver interface
 *
 * Register offsets and bit positions here MUST match, bit-for-bit,
 * rtl/common/parameters.vh (REG_ADDR_*) and rtl/common/types.vh
 * (CTRL_BIT_*, STAT_BIT_*, RESULT_BIT_*) -- these were cross-checked
 * against the actual RTL during Phase 4 (accelerator_registers_tb.v),
 * not re-derived independently here.
 *
 * ACCEL_BASE_ADDR: the accelerator's register block is mapped into a
 * reserved region of PicoRV32's address space, distinct from program and
 * data memory (HDS 3.6, "implementer-defined" integration decision).
 * 0x02000000 is the chosen value -- this MUST match soc_top.v's address
 * decode (Phase 6). If you change one, change the other.
 *============================================================================*/
#ifndef ACCELERATOR_DRIVER_H
#define ACCELERATOR_DRIVER_H

#include <stdint.h>

/* ---- base address (see note above -- must match soc_top.v) ---- */
#define ACCEL_BASE_ADDR   0x02000000u

/* ---- register byte offsets from ACCEL_BASE_ADDR, per HDS Table 4 ---- */
#define ACCEL_REG_CONTROL   0x00u
#define ACCEL_REG_STATUS    0x04u
#define ACCEL_REG_FEATURE0  0x08u
#define ACCEL_REG_FEATURE1  0x0Cu
#define ACCEL_REG_FEATURE2  0x10u
#define ACCEL_REG_FEATURE3  0x14u
#define ACCEL_REG_RESULT    0x18u

/* ---- CONTROL register bit positions, per rtl/common/types.vh ---- */
#define ACCEL_CTRL_BIT_START       0
#define ACCEL_CTRL_BIT_SOFT_RESET  1

/* ---- STATUS register bit positions, per rtl/common/types.vh ---- */
#define ACCEL_STAT_BIT_DONE   0
#define ACCEL_STAT_BIT_BUSY   1
#define ACCEL_STAT_BIT_ERROR  2

/* ---- RESULT register bit position, per rtl/common/types.vh ---- */
#define ACCEL_RESULT_BIT_PREDICTION 0

/* Number of input features (RMS, Peak, Kurtosis, Crest Factor), matches
 * NUM_FEATURES in rtl/common/parameters.vh / config.NUM_FEATURES. */
#define ACCEL_NUM_FEATURES 4

/*------------------------------------------------------------------------
 * accel_run_inference
 *
 * Writes the 4 Q8.8 features, pulses CONTROL.START, polls STATUS.DONE,
 * and returns the predicted class (0 = Normal, 1 = Fault) once done --
 * this is the C equivalent of what tb/integration/accelerator_top_tb.v
 * does in Verilog, driving the exact same register protocol.
 *
 * features: array of ACCEL_NUM_FEATURES signed Q8.8 int16 values, in
 *           FEATURE0..FEATURE3 order (RMS, Peak, Kurtosis, Crest Factor).
 * cycles_out: if non-NULL, receives the number of timer ticks the
 *             hardware inference took (for the Version 1 vs Version 2
 *             latency comparison) -- caller must have started/reset the
 *             timer immediately before calling this function.
 *
 * Returns: 0 (Normal) or 1 (Fault).
 *----------------------------------------------------------------------*/
uint8_t accel_run_inference(const int16_t features[ACCEL_NUM_FEATURES],
                             uint32_t *cycles_out);

/*------------------------------------------------------------------------
 * accel_soft_reset
 *
 * Pulses CONTROL.SOFT_RESET high then back low, returning the accelerator
 * to S_IDLE from any state. Not needed in normal operation (the hardware
 * returns to a ready state on its own after every inference), but useful
 * for recovering from an unexpected hang during bring-up/debug.
 *----------------------------------------------------------------------*/
void accel_soft_reset(void);

#endif /* ACCELERATOR_DRIVER_H */
