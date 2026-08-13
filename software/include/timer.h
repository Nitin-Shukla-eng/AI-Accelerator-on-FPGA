/*==============================================================================
 * timer.h
 * TinyRISC-TinyML -- cycle-count timing, using PicoRV32's native counter
 *
 * PicoRV32 (with the default ENABLE_COUNTERS=1) implements the standard
 * RISC-V `rdcycle`/`rdcycleh` CSR-read pseudo-instructions as a free-
 * running 64-bit cycle counter, reset to 0 at power-on/reset -- no custom
 * memory-mapped timer peripheral is needed. This wraps that counter for
 * the Version 1 (software) vs. Version 2 (hardware accelerator) latency
 * comparison main.c performs per test vector.
 *
 * If ENABLE_COUNTERS is ever disabled in the PicoRV32 instantiation
 * (rtl/cpu/picorv32.v parameters, Phase 6), timer_read_cycles() will
 * silently always return 0 -- worth checking that parameter stays at its
 * default if latency numbers ever look suspiciously flat.
 *============================================================================*/
#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>

/*------------------------------------------------------------------------
 * timer_read_cycles
 *
 * Returns the current value of PicoRV32's free-running cycle counter
 * (lower 32 bits -- sufficient for any single inference's latency; the
 * counter would need to run for ~35 seconds at 100 MHz to wrap, far
 * longer than any single measurement window here).
 *----------------------------------------------------------------------*/
uint32_t timer_read_cycles(void);

/*------------------------------------------------------------------------
 * timer_elapsed_cycles
 *
 * Returns the number of cycles elapsed between an earlier
 * timer_read_cycles() result (start) and now. Handles the (extremely
 * unlikely, given the note above) case of the counter wrapping between
 * start and now via unsigned subtraction, which is correct modulo 2^32
 * regardless of wraparound.
 *----------------------------------------------------------------------*/
static inline uint32_t timer_elapsed_cycles(uint32_t start) {
    return timer_read_cycles() - start;
}

#endif /* TIMER_H */
