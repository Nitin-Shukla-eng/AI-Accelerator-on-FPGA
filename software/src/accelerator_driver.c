/*==============================================================================
 * accelerator_driver.c
 * TinyRISC-TinyML -- Version 2 (hardware accelerator) driver implementation
 *
 * Drives the exact same register protocol as tb/integration/
 * accelerator_top_tb.v: write FEATURE0-3, pulse CONTROL.START, poll
 * STATUS.DONE, read RESULT. All register accesses go through `volatile`
 * pointers to prevent the compiler from reordering or caching them --
 * these are hardware side effects, not ordinary memory.
 *
 * Timing: the cycle count returned covers the FULL software-visible
 * latency of one inference -- the 4 feature writes, the START write, the
 * poll loop, and the RESULT read -- not just the accelerator's internal
 * cycle count. This is the correct, honest number for the Version 1 vs.
 * Version 2 comparison (AC-02): it's what software actually experiences,
 * including its own driving overhead, not an idealized hardware-only
 * figure.
 *============================================================================*/
#include "accelerator_driver.h"
#include "timer.h"

static inline void accel_write(uint32_t offset, uint32_t value) {
    *(volatile uint32_t *)(ACCEL_BASE_ADDR + offset) = value;
}

static inline uint32_t accel_read(uint32_t offset) {
    return *(volatile uint32_t *)(ACCEL_BASE_ADDR + offset);
}

uint8_t accel_run_inference(const int16_t features[ACCEL_NUM_FEATURES],
                             uint32_t *cycles_out) {
    uint32_t start_cycles = timer_read_cycles();

    /* Write the four Q8.8 features. Cast through uint16_t first so a
     * negative int16_t value reinterprets as its raw two's-complement bit
     * pattern (zero-extended into the 32-bit bus word) rather than being
     * sign-extended -- accelerator_registers.v only ever consumes the
     * lower 16 bits of bus_wdata, so this must match that exactly. */
    accel_write(ACCEL_REG_FEATURE0, (uint32_t)(uint16_t)features[0]);
    accel_write(ACCEL_REG_FEATURE1, (uint32_t)(uint16_t)features[1]);
    accel_write(ACCEL_REG_FEATURE2, (uint32_t)(uint16_t)features[2]);
    accel_write(ACCEL_REG_FEATURE3, (uint32_t)(uint16_t)features[3]);

    /* Pulse START. accelerator_registers.v derives a one-cycle internal
     * pulse from this write -- software does not need to (and must not)
     * write it back to 0 itself. */
    accel_write(ACCEL_REG_CONTROL, (uint32_t)1u << ACCEL_CTRL_BIT_START);

    /* Poll STATUS.DONE. Deliberately unbounded: a timeout here would mask
     * a genuine hardware hang rather than surface it during bring-up, and
     * every acceptance criterion (AC-01/AC-02) assumes the accelerator
     * always completes. */
    while (((accel_read(ACCEL_REG_STATUS) >> ACCEL_STAT_BIT_DONE) & 1u) == 0u) {
        /* busy-wait */
    }

    uint32_t result = accel_read(ACCEL_REG_RESULT);
    uint8_t prediction = (uint8_t)((result >> ACCEL_RESULT_BIT_PREDICTION) & 1u);

    if (cycles_out != 0) {
        *cycles_out = timer_elapsed_cycles(start_cycles);
    }

    return prediction;
}

void accel_soft_reset(void) {
    accel_write(ACCEL_REG_CONTROL, (uint32_t)1u << ACCEL_CTRL_BIT_SOFT_RESET);
    accel_write(ACCEL_REG_CONTROL, 0u); /* software must write it back to 0 */
}
