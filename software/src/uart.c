/*==============================================================================
 * uart.c
 * TinyRISC-TinyML -- UART driver implementation
 *
 * See uart.h for the register protocol this targets (matches simpleuart.v
 * / picosoc/firmware.c). All register accesses go through `volatile`
 * pointers -- these are hardware side effects, not ordinary memory.
 *============================================================================*/
#include "uart.h"

static inline void uart_write_reg(uint32_t offset, uint32_t value) {
    *(volatile uint32_t *)(UART_BASE_ADDR + offset) = value;
}

static inline uint32_t uart_read_reg(uint32_t offset) {
    return *(volatile uint32_t *)(UART_BASE_ADDR + offset);
}

void uart_init(uint32_t clkdiv) {
    uart_write_reg(UART_REG_CLKDIV, clkdiv);
}

void uart_putchar(char c) {
    if (c == '\n') {
        uart_putchar('\r');
    }
    /* Plain blocking store -- the hardware itself stalls the CPU until
     * ready (see uart.h). No software busy-poll loop here on purpose. */
    uart_write_reg(UART_REG_DATA, (uint32_t)(unsigned char)c);
}

void uart_puts(const char *s) {
    while (*s) {
        uart_putchar(*s++);
    }
}

void uart_print_dec(uint32_t value) {
    char buf[10]; /* max 10 digits for a 32-bit unsigned value (4294967295) */
    int i = 0;

    if (value == 0) {
        uart_putchar('0');
        return;
    }

    while (value > 0) {
        buf[i++] = (char)('0' + (value % 10));
        value /= 10;
    }
    while (i > 0) {
        uart_putchar(buf[--i]);
    }
}

void uart_print_hex(uint32_t value, int digits) {
    static const char hex_chars[] = "0123456789abcdef";

    if (digits < 1) digits = 1;
    if (digits > 8) digits = 8;

    for (int i = digits - 1; i >= 0; i--) {
        uart_putchar(hex_chars[(value >> (4 * i)) & 0xFu]);
    }
}

int uart_getchar_nonblock(void) {
    /* uart_read_reg returns 0xFFFFFFFF when no byte is available (see
     * uart.h); reinterpreting as int32_t turns that into -1, the sentinel
     * this function's callers check for. */
    return (int)(int32_t)uart_read_reg(UART_REG_DATA);
}
