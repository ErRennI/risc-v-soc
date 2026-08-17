// ============================================================
// File    : kbd_raw_dump.c
// Purpose : Diagnostic tool — dumps every raw byte KEYBOARD_REG
//           produces as hex over UART, bypassing keyboard.c's
//           decode/dedupe entirely. Used to see the actual PS/2
//           byte stream from a USB->PS2 legacy converter so
//           repeat/duplicate/missing-key behavior can be
//           diagnosed at the wire level instead of guessed at.
//
// Build (hardware): make compile_kbd_raw_dump
// ============================================================

#include "../drivers/uart.h"
#include "../drivers/keyboard.h"

static void uart_hex8(unsigned int v)
{
    unsigned int n;
    n = (v >> 4) & 0xFu;
    uart_putc((char)(n < 10u ? '0' + n : 'A' + n - 10u));
    n = v & 0xFu;
    uart_putc((char)(n < 10u ? '0' + n : 'A' + n - 10u));
}

int main(void)
{
    while (1) {
        unsigned int reg = *KEYBOARD_REG;
        if (reg & (1U << 8)) {
            unsigned char code = (unsigned char)(reg & 0xFF);
            uart_hex8(code);
            uart_putc(' ');
        }
    }

    return 0;
}
