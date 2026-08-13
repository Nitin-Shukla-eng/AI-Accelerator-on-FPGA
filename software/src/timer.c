/*==============================================================================
 * timer.c
 * TinyRISC-TinyML -- cycle-count timing implementation
 *
 * Uses the exact `rdcycle` inline-assembly idiom from PicoRV32's own
 * firmware/stats.c example (picorv32-1.0/firmware/stats.c), rather than a
 * hand-rolled CSR encoding, to avoid any risk of an incorrect immediate/
 * instruction encoding for this pseudo-instruction.
 *============================================================================*/
#include "timer.h"

uint32_t timer_read_cycles(void) {
    uint32_t cycles;
    __asm__ volatile ("rdcycle %0;" : "=r"(cycles));
    return cycles;
}
