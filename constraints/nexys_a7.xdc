# ============================================================
# Constraints : Digilent Nexys A7-100T (Artix-7 XC7A100T)
# Top module  : nexys_a7_top
# Notes       : cpu_rst_btn is the dedicated CPU_RESETN button
#               (C12, active LOW). nexys_a7_top inverts and
#               synchronizes it into rst_n internally.
#               All other buttons/switches are active-HIGH.
# ============================================================

# --- 100 MHz system clock ---
set_property PACKAGE_PIN E3    [get_ports clk_100mhz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100mhz]
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk_100mhz]

# --- CPU reset (CPU_RESETN, active low, pin C12) ---
set_property PACKAGE_PIN C12   [get_ports cpu_rst_btn]
set_property IOSTANDARD LVCMOS33 [get_ports cpu_rst_btn]

# --- USB-UART bridge ---
set_property PACKAGE_PIN D4    [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property PACKAGE_PIN C4    [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

# --- 16 LEDs ---
set_property PACKAGE_PIN H17   [get_ports {leds[0]}]
set_property PACKAGE_PIN K15   [get_ports {leds[1]}]
set_property PACKAGE_PIN J13   [get_ports {leds[2]}]
set_property PACKAGE_PIN N14   [get_ports {leds[3]}]
set_property PACKAGE_PIN R18   [get_ports {leds[4]}]
set_property PACKAGE_PIN V17   [get_ports {leds[5]}]
set_property PACKAGE_PIN U17   [get_ports {leds[6]}]
set_property PACKAGE_PIN U16   [get_ports {leds[7]}]
set_property PACKAGE_PIN V16   [get_ports {leds[8]}]
set_property PACKAGE_PIN T15   [get_ports {leds[9]}]
set_property PACKAGE_PIN U14   [get_ports {leds[10]}]
set_property PACKAGE_PIN T16   [get_ports {leds[11]}]
set_property PACKAGE_PIN V15   [get_ports {leds[12]}]
set_property PACKAGE_PIN V14   [get_ports {leds[13]}]
set_property PACKAGE_PIN V12   [get_ports {leds[14]}]
set_property PACKAGE_PIN V11   [get_ports {leds[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {leds[*]}]

# --- 16 slide switches ---
set_property PACKAGE_PIN J15   [get_ports {switches[0]}]
set_property PACKAGE_PIN L16   [get_ports {switches[1]}]
set_property PACKAGE_PIN M13   [get_ports {switches[2]}]
set_property PACKAGE_PIN R15   [get_ports {switches[3]}]
set_property PACKAGE_PIN R17   [get_ports {switches[4]}]
set_property PACKAGE_PIN T18   [get_ports {switches[5]}]
set_property PACKAGE_PIN U18   [get_ports {switches[6]}]
set_property PACKAGE_PIN R13   [get_ports {switches[7]}]
set_property PACKAGE_PIN T8    [get_ports {switches[8]}]
set_property PACKAGE_PIN U8    [get_ports {switches[9]}]
set_property PACKAGE_PIN R16   [get_ports {switches[10]}]
set_property PACKAGE_PIN T13   [get_ports {switches[11]}]
set_property PACKAGE_PIN H6    [get_ports {switches[12]}]
set_property PACKAGE_PIN U12   [get_ports {switches[13]}]
set_property PACKAGE_PIN U11   [get_ports {switches[14]}]
set_property PACKAGE_PIN V10   [get_ports {switches[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {switches[*]}]

# --- 5 push buttons: BTNU[0], BTNL[1], BTNR[2], BTND[3], BTNC[4] ---
set_property PACKAGE_PIN M18   [get_ports {buttons[0]}]
set_property PACKAGE_PIN P17   [get_ports {buttons[1]}]
set_property PACKAGE_PIN M17   [get_ports {buttons[2]}]
set_property PACKAGE_PIN P18   [get_ports {buttons[3]}]
set_property PACKAGE_PIN N17   [get_ports {buttons[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {buttons[*]}]

# --- 7-segment display anodes (active LOW) ---
set_property PACKAGE_PIN J17   [get_ports {an[0]}]
set_property PACKAGE_PIN J18   [get_ports {an[1]}]
set_property PACKAGE_PIN T9    [get_ports {an[2]}]
set_property PACKAGE_PIN J14   [get_ports {an[3]}]
set_property PACKAGE_PIN P14   [get_ports {an[4]}]
set_property PACKAGE_PIN T14   [get_ports {an[5]}]
set_property PACKAGE_PIN K2    [get_ports {an[6]}]
set_property PACKAGE_PIN U13   [get_ports {an[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[*]}]

# --- 7-segment cathodes CA–CG (active LOW) and DP ---
set_property PACKAGE_PIN T10   [get_ports {seg[0]}]
set_property PACKAGE_PIN R10   [get_ports {seg[1]}]
set_property PACKAGE_PIN K16   [get_ports {seg[2]}]
set_property PACKAGE_PIN K13   [get_ports {seg[3]}]
set_property PACKAGE_PIN P15   [get_ports {seg[4]}]
set_property PACKAGE_PIN T11   [get_ports {seg[5]}]
set_property PACKAGE_PIN L18   [get_ports {seg[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[*]}]

set_property PACKAGE_PIN H15   [get_ports dp]
set_property IOSTANDARD LVCMOS33 [get_ports dp]

# --- SPI flash (N25Q128A) ---
# CCLK is driven via STARTUPE2 — no pin constraint needed for SCK.
# Verify these assignments against Digilent's Nexys A7 Master XDC.
set_property PACKAGE_PIN L13   [get_ports flash_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports flash_cs_n]
set_property PACKAGE_PIN K17   [get_ports flash_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports flash_mosi]
set_property PACKAGE_PIN K18   [get_ports flash_miso]
set_property IOSTANDARD LVCMOS33 [get_ports flash_miso]
set_property PACKAGE_PIN L14   [get_ports flash_wp_n]
set_property IOSTANDARD LVCMOS33 [get_ports flash_wp_n]
set_property PACKAGE_PIN M14   [get_ports flash_hold_n]
set_property IOSTANDARD LVCMOS33 [get_ports flash_hold_n]

# --- Async input timing exceptions ---
set_false_path -from [get_ports cpu_rst_btn]
set_false_path -from [get_ports uart_rx]
set_false_path -from [get_ports {switches[*]}]
set_false_path -from [get_ports {buttons[*]}]

# --- Bitstream config (Nexys A7 standard) ---
set_property CONFIG_VOLTAGE 3.3              [current_design]
set_property CFGBVS VCCO                     [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE  33 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

## ====================================================================
## VGA SYNC SIGNALS
## ====================================================================
set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { hsync }];
set_property -dict { PACKAGE_PIN B12   IOSTANDARD LVCMOS33 } [get_ports { vsync }];

## ====================================================================
## VGA RED (vga_r[0] - vga_r[3])
## ====================================================================
set_property -dict { PACKAGE_PIN A3    IOSTANDARD LVCMOS33 } [get_ports { vga_r[0] }];
set_property -dict { PACKAGE_PIN B4    IOSTANDARD LVCMOS33 } [get_ports { vga_r[1] }];
set_property -dict { PACKAGE_PIN C5    IOSTANDARD LVCMOS33 } [get_ports { vga_r[2] }];
set_property -dict { PACKAGE_PIN A4    IOSTANDARD LVCMOS33 } [get_ports { vga_r[3] }];

## ====================================================================
## VGA GREEN (vga_g[0] - vga_g[3])
## ====================================================================
set_property -dict { PACKAGE_PIN C6    IOSTANDARD LVCMOS33 } [get_ports { vga_g[0] }];
set_property -dict { PACKAGE_PIN A5    IOSTANDARD LVCMOS33 } [get_ports { vga_g[1] }];
set_property -dict { PACKAGE_PIN B6    IOSTANDARD LVCMOS33 } [get_ports { vga_g[2] }];
set_property -dict { PACKAGE_PIN A6    IOSTANDARD LVCMOS33 } [get_ports { vga_g[3] }];

## ====================================================================
## VGA BLUE (vga_b[0] - vga_b[3])
## ====================================================================
set_property -dict { PACKAGE_PIN B7    IOSTANDARD LVCMOS33 } [get_ports { vga_b[0] }];
set_property -dict { PACKAGE_PIN C7    IOSTANDARD LVCMOS33 } [get_ports { vga_b[1] }];
set_property -dict { PACKAGE_PIN D7    IOSTANDARD LVCMOS33 } [get_ports { vga_b[2] }];
set_property -dict { PACKAGE_PIN D8    IOSTANDARD LVCMOS33 } [get_ports { vga_b[3] }];

##=============================================================================
## PS/2 Keyboard Pins (Nexys A7)
##=============================================================================
set_property -dict { PACKAGE_PIN F4    IOSTANDARD LVCMOS33 } [get_ports { ps2_clk }];
set_property -dict { PACKAGE_PIN B2    IOSTANDARD LVCMOS33 } [get_ports { ps2_data }];

## Internal pull-ups for signal stability (critical for PS/2 open-drain lines)
set_property PULLUP true [get_ports ps2_clk]
set_property PULLUP true [get_ports ps2_data]
