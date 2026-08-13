/*==============================================================================
 * uart.h
 * TinyRISC-TinyML -- UART driver interface
 *
 * Targets the real `simpleuart.v` module from the PicoRV32 distribution
 * (picorv32-1.0/picosoc/simpleuart.v) -- reused as-is in soc_top.v
 * (Phase 6) rather than a custom UART peripheral, for the same reason
 * PicoRV32 itself is reused rather than written from scratch: it's a
 * proven module.
 *
 * Register protocol (matches simpleuart.v / picosoc/firmware.c exactly):
 *   UART_DATA write : transmit one byte. The hardware itself stalls the
 *                      CPU (via simpleuart's reg_dat_wait -> soc_top.v's
 *                      mem_ready gating) until the UART is ready to accept
 *                      it -- so this is a plain blocking store from
 *                      software's point of view, no busy-poll needed here.
 *   UART_DATA read  : returns the next received byte in bits [7:0], or
 *                      0xFFFFFFFF (-1 as int32_t) if none is available yet.
 *   UART_CLKDIV     : baud-rate divider, write once during uart_init().
 *
 * UART_BASE_ADDR: chosen to avoid the accelerator's 0x02000000 region
 * (see accelerator_driver.h) -- MUST match soc_top.v's address decode
 * when that's built in Phase 6.
 *============================================================================*/
#ifndef UART_H
#define UART_H

#include <stdint.h>

#define UART_BASE_ADDR        0x03000000u
#define UART_REG_CLKDIV       0x00u
#define UART_REG_DATA         0x04u

/*------------------------------------------------------------------------
 * uart_init
 *
 * clkdiv: (system_clock_hz / baud_rate), per simpleuart.v's cfg_divider.
 * E.g. for a 100 MHz system clock and 115200 baud: clkdiv = 100000000/115200 ~= 868.
 * Call once at startup before any other uart_* function.
 *----------------------------------------------------------------------*/
void uart_init(uint32_t clkdiv);

/*------------------------------------------------------------------------
 * uart_putchar
 *
 * Transmits one byte, blocking (via hardware stall, not software polling)
 * until the UART is ready. Translates '\n' to "\r\n", matching the
 * picosoc firmware.c convention terminal programs expect.
 *----------------------------------------------------------------------*/
void uart_putchar(char c);

/*------------------------------------------------------------------------
 * uart_puts
 *
 * Transmits a NUL-terminated string via repeated uart_putchar().
 *----------------------------------------------------------------------*/
void uart_puts(const char *s);

/*------------------------------------------------------------------------
 * uart_print_dec
 *
 * Transmits an unsigned 32-bit value in decimal, no leading zeros.
 * Used for reporting cycle counts and vector indices.
 *----------------------------------------------------------------------*/
void uart_print_dec(uint32_t value);

/*------------------------------------------------------------------------
 * uart_print_hex
 *
 * Transmits `digits` hex digits of `value` (most significant first),
 * lowercase a-f. Used for register/status dumps during debug.
 *----------------------------------------------------------------------*/
void uart_print_hex(uint32_t value, int digits);

/*------------------------------------------------------------------------
 * uart_getchar_nonblock
 *
 * Returns the next received byte (0-255), or -1 if none is available.
 * Not used by main.c's test-vector loop, but useful for interactive
 * debug during bring-up.
 *----------------------------------------------------------------------*/
int uart_getchar_nonblock(void);

#endif /* UART_H */
