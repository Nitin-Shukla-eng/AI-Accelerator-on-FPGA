/*==============================================================================
 * start.S
 * TinyRISC-TinyML -- minimal startup code
 *
 * Deliberately simpler than either PicoRV32 reference example
 * (picosoc/start.s has flash-to-RAM copy + SPI flash worker code this
 * project doesn't need since there's no external flash; firmware/start.S
 * has interrupt handling this project doesn't need per the frozen design
 * decision of no interrupts anywhere in the datapath). Kept: the
 * zero-all-registers and explicit .bss-zero patterns from both references
 * -- relying on BRAM powering up as zero is not a portable guarantee.
 *
 * .data does NOT need a runtime copy step here (unlike picosoc's flash+
 * RAM split): this project uses one unified RAM (sections.lds), so
 * .data's initial values are already correct in the memory image as
 * loaded -- there's nothing to copy from.
 *============================================================================*/
    .section .text.start
    .global _start

_start:
    /* zero-initialize every general-purpose register */
    addi x1,  zero, 0
    addi x3,  zero, 0
    addi x4,  zero, 0
    addi x5,  zero, 0
    addi x6,  zero, 0
    addi x7,  zero, 0
    addi x8,  zero, 0
    addi x9,  zero, 0
    addi x10, zero, 0
    addi x11, zero, 0
    addi x12, zero, 0
    addi x13, zero, 0
    addi x14, zero, 0
    addi x15, zero, 0
    addi x16, zero, 0
    addi x17, zero, 0
    addi x18, zero, 0
    addi x19, zero, 0
    addi x20, zero, 0
    addi x21, zero, 0
    addi x22, zero, 0
    addi x23, zero, 0
    addi x24, zero, 0
    addi x25, zero, 0
    addi x26, zero, 0
    addi x27, zero, 0
    addi x28, zero, 0
    addi x29, zero, 0
    addi x30, zero, 0
    addi x31, zero, 0

    /* set stack pointer (x2) to the top of RAM, per sections.lds */
    la sp, _stack_top

    /* zero-initialize the .bss section */
    la a0, _sbss
    la a1, _ebss
    bge a0, a1, bss_zero_done
bss_zero_loop:
    sw zero, 0(a0)
    addi a0, a0, 4
    blt a0, a1, bss_zero_loop
bss_zero_done:

    /* call main -- never expected to return (main.c halts in an
     * infinite loop), but loop forever afterward regardless, just in
     * case, rather than falling through into unrelated memory. */
    call main
halt:
    j halt
