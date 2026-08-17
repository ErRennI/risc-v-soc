#include "vga.h"

void vga_clear_line_range(int start_x, int y, int len) {
    for (int k = 0; k < len; k++) {
        vga_write_char(start_x + k, y, ' ', VGA_COLOR_BLACK);
    }
}

int vga_print_int(int x, int y, int number, unsigned char color) {
    unsigned char buffer[12];
    int i = 0;
    int is_negative = 0;
    unsigned int n;
    int current_x = x;


    //DOESNT print 0
    if(number == 0) {
        vga_write_char(x, y, '0', color);
        return current_x++;
    }

    if(number < 0) {
        is_negative = 1;
        n = (unsigned int)(-(number + 1)) + 1;
    } else {
        n = (unsigned int)number;
    }

    while(n > 0) {
        int digit = n % 10;
        buffer[i++] = (char)(digit + '0');
        n = n / 10;
    }
    
    if(is_negative) {
        buffer[i++] = '-';
    }

    for(int j = i - 1; j >= 0; j--) {
        if(current_x >= 80) {
            current_x = 0;
            y++;
        }

        if(y >= 60) {
            break;
        }

        vga_write_char(current_x, y,buffer[j], color);
        current_x++;
    }

    return current_x;
}

void vga_write_char(int x, int y, unsigned char ascii_code, unsigned char color) {
    if (x < 0 || x >= VGA_COLS || y < 0 || y >= VGA_ROWS) {
        return;
    }

    int vram_index = (y * 80) + x;
    //No attribute for now it can stay like this
    unsigned short data = ((unsigned short)(color & 0xF) << 8) | ascii_code;

    VGA_VRAM[vram_index] = data;
}

void vga_print_str(int x, int y, const char *str, unsigned char color) {
    int current_x = x;
    while(*str) {
        if(*str == '\n') {
            current_x = 0; //Continues from start of a new line not block
            y++;
            str++;
            continue;
        }

        if(current_x >= VGA_COLS) {
            current_x = 0;
            y++;
        }

        if(y >= VGA_ROWS) {
            break;
        }

        vga_write_char(current_x, y, (unsigned char)(*str), color);
        current_x++;
        str++;
    }
}

//VGA hardware clear
void vga_clear_screen(void) {
    *VGA_STATUS_REG = (1U << 31);

    while((*VGA_STATUS_REG & 0x1) == 0) {

    }
}

void vga_init(void) {
    vga_clear_screen();
}