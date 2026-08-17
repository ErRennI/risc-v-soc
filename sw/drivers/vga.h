#ifndef VGA_H
#define VGA_H

/*
    MMIO VGA ADDRES
*/
#define VGA_BASE_ADDR 0x40005000
#define VGA_VRAM ((volatile unsigned short*)VGA_BASE_ADDR)
#define VGA_STATUS_REG ((volatile unsigned int*)VGA_BASE_ADDR)

#define VGA_COLS 80
#define VGA_ROWS 60
#define VGA_TOTAL_TILES 4800

#define VGA_COLOR_BLACK       0x0
#define VGA_COLOR_DARK_BLUE   0x1
#define VGA_COLOR_DARK_GREEN  0x2
#define VGA_COLOR_CYAN        0x3
#define VGA_COLOR_DARK_RED    0x4
#define VGA_COLOR_MAGENTA     0x5
#define VGA_COLOR_BROWN       0x6
#define VGA_COLOR_LIGHT_GREY  0x7
#define VGA_COLOR_DARK_GREY   0x8
#define VGA_COLOR_LIGHT_BLUE  0x9
#define VGA_COLOR_LIGHT_GREEN 0xA
#define VGA_COLOR_LIGHT_CYAN  0xB
#define VGA_COLOR_LIGHT_RED   0xC
#define VGA_COLOR_PINK        0xD
#define VGA_COLOR_YELLOW      0xE
#define VGA_COLOR_WHITE       0xF

void vga_init(void);
void vga_write_char(int x, int y, unsigned char ascii_code, unsigned char color);
void vga_clear_screen(void);
void vga_print_str(int x, int y, const char *str, unsigned char color);
int vga_print_int(int x, int y, int number, unsigned char color);
void vga_clear_line_range(int start_x, int y, int len);

#endif