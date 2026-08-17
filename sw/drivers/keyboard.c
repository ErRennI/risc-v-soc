#include "keyboard.h"

static volatile char kbd_buffer_char;
static volatile int kbd_buffer_ready;

int kbd_is_key_pressed(void) {
    return (*KEYBOARD_REG & (1U << 8)) ? 1 : 0;
}

static char kbd_scancode_to_ascii(unsigned char scancode) {
    switch (scancode) {
        case 0x1C: return 'A'; case 0x32: return 'B'; case 0x21: return 'C';
        case 0x23: return 'D'; case 0x24: return 'E'; case 0x2B: return 'F';
        case 0x34: return 'G'; case 0x33: return 'H'; case 0x43: return 'I';
        case 0x3B: return 'J'; case 0x42: return 'K'; case 0x4B: return 'L';
        case 0x3A: return 'M'; case 0x31: return 'N'; case 0x44: return 'O';
        case 0x4D: return 'P'; case 0x15: return 'Q'; case 0x2D: return 'R';
        case 0x1B: return 'S'; case 0x2C: return 'T'; case 0x3C: return 'U';
        case 0x2A: return 'V'; case 0x1D: return 'W'; case 0x22: return 'X';
        case 0x35: return 'Y'; case 0x1A: return 'Z';
        
        case 0x45: return '0'; case 0x16: return '1'; case 0x1E: return '2';
        case 0x26: return '3'; case 0x25: return '4'; case 0x2E: return '5';
        case 0x36: return '6'; case 0x3D: return '7'; case 0x3E: return '8';
        case 0x46: return '9';
        
        case 0x29: return ' ';    // Space
        case 0x5A: return '\n';   // Enter
        case 0x66: return '\b';   // Backspace
        default:   return 0;
    }
}

// Waits for an keyboard input BLOCKING
char kbd_get_char_blocking(void) {
    while(!kbd_buffer_ready) {

    }
    kbd_buffer_ready = 0;
    return kbd_buffer_char;
}

// NON-BLOCKING
int kbd_has_char(void) {
    return kbd_buffer_ready;
}

char kbd_get_char_nonblocking() {
    if(!kbd_buffer_ready) {
        return 0;
    }

    kbd_buffer_ready = 0;
    return kbd_buffer_char;
}

//ISR HANDLER
void keyboard_isr_handler(void) {
    static int is_break_code;
    // Some USB->PS2 legacy converters don't send a reliable break code, so
    // dedupe can't wait for one. Instead: suppress only a single immediate
    // repeat of the same make code (the accidental double-fire from one
    // physical tap), then reset so the same key can be pressed again.
    static unsigned char last_code;
    static int last_was_duplicate;

    // Single read: KEYBOARD_REG clears the ready bit on any read, so
    // reading ready and scancode separately risks the scancode read
    // racing a newly-arrived byte. One read returns both atomically.
    unsigned int reg = *KEYBOARD_REG;

    if (reg & (1U << 8)) {
        unsigned char code = (unsigned char)(reg & 0xFF);
        if (code == 0xF0) { is_break_code = 1; return; }

        if (is_break_code) {
            is_break_code = 0;
            // A real break proves this key was actually released, so any
            // pending "next same code is a duplicate" state for it is stale
            // — the next make of this code is unambiguously a fresh press.
            if (code == last_code) { last_code = 0; last_was_duplicate = 0; }
            return;   // breaks never produce output
        }

        if (code == last_code && !last_was_duplicate) {
            last_was_duplicate = 1;   // swallow exactly one repeat
            return;
        }

        last_code = code;
        last_was_duplicate = 0;

        char c = kbd_scancode_to_ascii(code);
        if (c != 0) {
            kbd_buffer_char = c;
            kbd_buffer_ready = 1;
        }
    }
}