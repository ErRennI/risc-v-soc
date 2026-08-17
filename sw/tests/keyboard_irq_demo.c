// ============================================================
// File    : keyboard_irq_demo.c
// Purpose : PS2 keyboard external-interrupt demo for RV32IM SoC.
//
// - ps2_keyboard.sv drives irq_m_external (mcause 0x8000000B).
// - ISR calls keyboard_isr_handler() to decode + buffer the char.
// - Main loop echoes buffered chars over UART.
//
// Build (hardware): make compile_keyboard_irq_demo
// ============================================================

#include "../drivers/uart.h"
#include "../drivers/keyboard.h"

void __attribute__((interrupt("machine"))) machine_trap_handler(void)
{
    unsigned int mcause;
    __asm__ volatile ("csrrs %0, mcause, x0" : "=r"(mcause));

    if (mcause == 0x8000000Bu) {
        keyboard_isr_handler();
    }
}

static void uart_str(const char *s)
{
    while (*s) uart_putc(*s++);
}

int main(void)
{

    // Point MTVEC at our ISR (direct mode, bits[1:0]=00)
    __asm__ volatile ("csrrw x0, mtvec, %0" :: "r"((unsigned int)machine_trap_handler));

    // Enable machine external interrupt in MIE (bit 11 = MEIE)
    { unsigned int meie = 0x800u;
      __asm__ volatile ("csrrs x0, mie, %0" :: "r"(meie)); }

    // Enable global machine interrupts in MSTATUS (bit 3 = MIE)
    __asm__ volatile ("csrrsi x0, mstatus, 0x8");

    for (;;) {
        if (kbd_has_char()) {
            char c = kbd_get_char_nonblocking();
            uart_putc(c);
        }
    }

    return 0;
}
