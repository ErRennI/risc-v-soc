#ifndef KEYBOARD_H
#define KEYBOARD_H

#define KEYBOARD_BASE_ADDR 0x40008000
#define KEYBOARD_REG ((volatile unsigned int*)KEYBOARD_BASE_ADDR)


int kbd_is_key_pressed(void);

//ISR handler
void keyboard_isr_handler(void);

//Non-blocking functions
int kbd_has_char(void);
char kbd_get_char_nonblocking(void);

char kbd_get_char_blocking(void);

#endif