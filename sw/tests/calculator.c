// ============================================================
// File    : calculator.c
// Purpose : Interactive calculator demo for RV32IM SoC, driven
//           entirely from a PS/2 keyboard.
//
// Inputs  : 0-9      → digits for operand A / operand B
//           a/s/m/d  → operator: add / subtract / multiply / divide
//           Enter    → 1st press previews the current field,
//                      2nd press commits it and advances
//                      (operand A -> operator -> operand B -> result)
//           Backspace→ deletes last char, or steps back to the
//                      previous field once the current one is empty
//
// Outputs : VGA  → live centered "A op B = R" as it's typed
//
// Design  : Pure polling, no interrupts — keyboard_isr_handler()
//           is called directly each loop iteration (mtvec/mie/
//           mstatus are never touched). A small state machine
//           (ENTER_A/ENTER_OP/ENTER_B/RESULT) drives entry; the
//           whole expression typed so far is redrawn each
//           keystroke, clearing only the previously drawn span
//           (prev_start_x/prev_total_len) rather than the full row.
// ============================================================

#include "../drivers/vga.h"
#include "../drivers/keyboard.h"

static char op_symbol(char op_letter)
{
    switch (op_letter) {
        case 'A': return '+';
        case 'S': return '-';
        case 'M': return '*';
        case 'D': return '/';
        default:  return 0;
    }
}

static int get_int_len(int number) {
    if (number == 0) return 1;

    int len = 0;
    unsigned int n;

    if (number < 0) {
        len = 1;
        n = (unsigned int)(-(number + 1)) + 1;
    } else {
        n = (unsigned int)number;
    }

    if (n >= 1000000000u) return len + 10;
    if (n >= 100000000u)  return len + 9;
    if (n >= 10000000u)   return len + 8;
    if (n >= 1000000u)    return len + 7;
    if (n >= 100000u)     return len + 6;
    if (n >= 10000u)      return len + 5;
    if (n >= 1000u)       return len + 4;
    if (n >= 100u)        return len + 3;
    if (n >= 10u)         return len + 2;

    return len + 1;
}

static unsigned int str_to_uint(const char *s, int *overflow) {
    unsigned int v = 0;
    while(*s) {
        unsigned int digit = (unsigned int)(*s - '0');
        if (v > (0xFFFFFFFFu - digit) / 10u) *overflow = 1;
        v = v * 10u + digit;
        s++;
    }
    return v;
}

static int str_len(const char *s) {
    int n = 0;
    while (*s++) n++;
    return n;
}

typedef enum {ENTER_A, ENTER_OP, ENTER_B, RESULT} calc_state_t;

static const char *status_text(calc_state_t state, int previewed) {
    switch (state) {
        case ENTER_A:
            return previewed ? "Operand A ready - press Enter again to confirm"
                              : "Enter operand A (0-9) - Enter to confirm, Backspace to edit";
        case ENTER_OP:
            return previewed ? "Operator ready - press Enter again to confirm"
                              : "Choose operator - A:+  S:-  M:*  D:/";
        case ENTER_B:
            return previewed ? "Operand B ready - press Enter again to confirm"
                              : "Enter operand B (0-9) - Enter to confirm, Backspace to edit";
        case RESULT:
            return "Result shown below - press any key to start a new calculation";
    }
    return "";
}

int main(void)
{
    vga_init();
    calc_state_t state = ENTER_A;
    char buff_a[12] = {0}, buff_b[12] = {0};
    int len_a = 0, len_b = 0;
    char op = 0;
    int previewed = 0;
    int prev_start_x = 0;
    int prev_total_len = 0;
    int prev_status_len = 0;

    // Controls legend — written once, never cleared, so it always stays put.
    vga_print_str(0, 0,
        "0-9:digits  A:+ S:- M:* D:/  Enter:confirm(x2)  Backspace:edit/back",
        VGA_COLOR_LIGHT_GREY);

    while (1) {
        keyboard_isr_handler();
        if(!kbd_has_char()) continue;

        char c = kbd_get_char_nonblocking();

        switch(state) {
            case ENTER_A: 
                if(c >= '0' && c <= '9') {
                    if(len_a < (int)sizeof(buff_a) - 1) {
                        buff_a[len_a] = c;
                        len_a++;
                        buff_a[len_a] = '\0'; 
                    }
                    previewed = 0;
                } else if(c == '\b') {
                    if(len_a > 0) {
                        len_a--;
                        buff_a[len_a] = '\0';
                        previewed = 0;
                    }
                } else if(c == '\n') {
                    if(!previewed) previewed = 1;
                    else {
                        state = ENTER_OP;
                        previewed = 0;
                    }
                }
                break;
            case ENTER_OP:
                if(c == 'A' || c == 'S' || c == 'M' || c == 'D') {
                    op = c;
                    previewed = 0;
                } else if(c == '\b') {
                    if(op != 0) {
                        op = 0;
                        previewed = 0;
                    } else {
                        state = ENTER_A;
                        previewed = 0;
                    }
                } else if(c == '\n') {
                    if (op == 0) break;
                    if(!previewed) previewed = 1;
                    else {
                        state = ENTER_B;
                        previewed = 0;
                    }
                }
                break;
            case  ENTER_B:
                if(c >= '0' && c <= '9') {
                    if(len_b < (int)sizeof(buff_b) - 1) {
                        buff_b[len_b] = c;
                        len_b++;
                        buff_b[len_b] = '\0';
                    }
                    previewed = 0;
                } else if(c == '\b') {
                    if(len_b > 0) {
                        len_b--;
                        buff_b[len_b] = '\0';
                        previewed = 0;
                    } else {
                        state = ENTER_OP;
                        previewed = 0;
                    }
                } else if(c == '\n') {
                    if(!previewed) previewed = 1;
                    else {
                        state = RESULT;
                        previewed = 0;
                    }
                }
                break;
            case RESULT:
                state = ENTER_A;
                len_a = 0; len_b = 0;
                buff_a[0] = '\0'; buff_b[0] = '\0';
                op = 0; previewed = 0;
                break;
        }

        int n = len_a;
        if(op != 0) n += 3;
        n += len_b;

        unsigned int a = 0;
        unsigned int b = 0;
        unsigned int result = 0;
        int overflow = 0;

        if(state == RESULT) {
            a = str_to_uint(buff_a, &overflow);
            b = str_to_uint(buff_b, &overflow);

            switch(op) {
                case 'A':
                    result = a + b;
                    if (result < a) overflow = 1;
                    break;
                case 'S':
                    result = a - b;
                    break;
                case 'M':
                    result = a * b;
                    if (a != 0 && result / a != b) overflow = 1;
                    break;
                case 'D':
                    result = b ? a / b : 0xFFFFFFFFu;
                    break;
            }
            n += 3 + (overflow ? str_len("OVERFLOW") : get_int_len((int)result));
        }

        const char *status = status_text(state, previewed);
        int status_len = str_len(status);
        if (prev_status_len > 0) {
            vga_clear_line_range(0, 25, prev_status_len);
        }
        vga_print_str(0, 25, status, VGA_COLOR_CYAN);
        prev_status_len = status_len;

        int curr_x = (80 - n) / 2;
        if(prev_total_len > 0 ) {
            vga_clear_line_range(prev_start_x, 28, prev_total_len);
        }

        prev_start_x = curr_x;
        prev_total_len = n;

        vga_print_str(curr_x, 28, buff_a, VGA_COLOR_WHITE);
        curr_x += len_a;
        if (op != 0) {
            vga_write_char(curr_x++, 28, ' ', VGA_COLOR_WHITE);
            vga_write_char(curr_x++, 28, op_symbol(op), VGA_COLOR_YELLOW);
            vga_write_char(curr_x++, 28, ' ', VGA_COLOR_WHITE);
        }

        vga_print_str(curr_x, 28, buff_b, VGA_COLOR_WHITE);
        curr_x += len_b;

        if(state == RESULT) {
            vga_write_char(curr_x++, 28, ' ', VGA_COLOR_WHITE);
            vga_write_char(curr_x++, 28, '=', VGA_COLOR_YELLOW);
            vga_write_char(curr_x++, 28, ' ', VGA_COLOR_WHITE);
            if (overflow) {
                vga_print_str(curr_x, 28, "OVERFLOW", VGA_COLOR_LIGHT_RED);
            } else {
                curr_x = vga_print_int(curr_x, 28, (int)result, VGA_COLOR_DARK_GREEN);
            }
        }
        
    }

    return 0;
}
