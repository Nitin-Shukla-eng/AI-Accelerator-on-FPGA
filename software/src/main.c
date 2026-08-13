/*==============================================================================
 * main.c
 * TinyRISC-TinyML -- test-vector runner, Version 1 (software) or
 * Version 2 (hardware accelerator), selected at BUILD time.
 *
 * Build with exactly one of:
 *   -DVERSION_SOFTWARE   -> links software_nn.c, runs the pure-C forward pass
 *   -DVERSION_HARDWARE   -> links accelerator_driver.c, drives the RTL accelerator
 * (see Makefile -- this produces two separate firmware images, per HDS/VIS.)
 *
 * Runs every vector in generated/software/test_vectors.h, checks the
 * prediction against generated/software/expected_outputs.h (the same
 * golden reference tb/integration/accelerator_top_tb.v was checked
 * against in Phase 4), and reports per-vector cycle counts plus a
 * summary over UART -- this output is the raw data for the Version 1 vs.
 * Version 2 latency comparison (AC-02) and the final results/comparison/
 * report (Phase 9).
 *
 * SYSTEM_CLOCK_HZ: placeholder until Phase 7 (Vivado synthesis/
 * implementation) finalizes the actual PYNQ-Z2 clock frequency --
 * override with -DSYSTEM_CLOCK_HZ=<value> once that's known, or this
 * firmware's reported baud rate will be wrong even though the cycle
 * counts themselves remain correct regardless of clock frequency.
 *============================================================================*/
#include <stdint.h>
#include "uart.h"
#include "timer.h"
#include "test_vectors.h"
#include "expected_outputs.h"

#if defined(VERSION_HARDWARE)
    #include "accelerator_driver.h"
#elif defined(VERSION_SOFTWARE)
    #include "software_nn.h"
#else
    #error "Define exactly one of VERSION_SOFTWARE or VERSION_HARDWARE (see Makefile)"
#endif

#ifndef SYSTEM_CLOCK_HZ
    #define SYSTEM_CLOCK_HZ 50000000u /* placeholder -- see file header note */
#endif

#ifndef UART_BAUD_RATE
    #define UART_BAUD_RATE 115200u
#endif

static uint8_t run_one_vector(int idx, uint32_t *cycles_out) {
#if defined(VERSION_HARDWARE)
    return accel_run_inference(test_vectors[idx], cycles_out);
#else
    uint32_t start = timer_read_cycles();
    uint8_t prediction = software_nn_infer(test_vectors[idx]);
    if (cycles_out != 0) {
        *cycles_out = timer_elapsed_cycles(start);
    }
    return prediction;
#endif
}

int main(void) {
    uart_init(SYSTEM_CLOCK_HZ / UART_BAUD_RATE);

    uart_puts("TinyRISC-TinyML test-vector run\n");
#if defined(VERSION_HARDWARE)
    uart_puts("Version: 2 (hardware accelerator)\n");
#else
    uart_puts("Version: 1 (software)\n");
#endif
    uart_puts("vectors: ");
    uart_print_dec((uint32_t)NUM_TEST_VECTORS);
    uart_puts("\n---\n");

    uint32_t total_cycles = 0;
    uint32_t correct = 0;

    for (int i = 0; i < NUM_TEST_VECTORS; i++) {
        uint32_t cycles = 0;
        uint8_t prediction = run_one_vector(i, &cycles);
        uint8_t expected = expected_outputs[i];
        uint8_t match = (prediction == expected) ? 1u : 0u;

        total_cycles += cycles;
        if (match) {
            correct++;
        }

        uart_puts("vector ");
        uart_print_dec((uint32_t)i);
        uart_puts(": prediction=");
        uart_print_dec((uint32_t)prediction);
        uart_puts(" expected=");
        uart_print_dec((uint32_t)expected);
        uart_puts(match ? " OK" : " MISMATCH");
        uart_puts(" cycles=");
        uart_print_dec(cycles);
        uart_puts("\n");
    }

    uart_puts("---\n");
    uart_puts("correct: ");
    uart_print_dec(correct);
    uart_puts("/");
    uart_print_dec((uint32_t)NUM_TEST_VECTORS);
    uart_puts("\n");
    uart_puts("total cycles: ");
    uart_print_dec(total_cycles);
    uart_puts("\n");
    uart_puts("avg cycles/inference: ");
    uart_print_dec(total_cycles / (uint32_t)NUM_TEST_VECTORS);
    uart_puts("\n");

    if (correct == (uint32_t)NUM_TEST_VECTORS) {
        uart_puts("RESULT: ALL VECTORS MATCH GOLDEN REFERENCE\n");
    } else {
        uart_puts("RESULT: MISMATCHES PRESENT\n");
    }

    while (1) {
        /* halt -- nothing more to do */
    }

    return 0;
}
