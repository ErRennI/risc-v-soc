// ============================================================
// Module  : nexys_a7_top
// Purpose : Board-level top wrapper for the Nexys A7-100T.
//           Inverts the active-LOW CPU_RESETN button to the
//           soc_top's active-LOW rst_n, runs the deassertion
//           edge through a 2-FF synchronizer to remove
//           metastability on rst_n release.
//           Drives the SoC directly from the board's 100 MHz
//           oscillator (the 50 MHz workaround is removed now
//           that the MDU multiplier path is pipelined).
//           Routes spi_sck through STARTUPE2 to reach CCLK —
//           the only way to drive the on-board flash clock on
//           Artix-7 after configuration is complete.
// ============================================================
module nexys_a7_top (
    // 100 MHz system clock from Nexys A7 oscillator (pin E3)
    input  logic        clk_100mhz,

    // CPU_RESETN — dedicated reset button, active LOW (pin C12).
    input  logic        cpu_rst_btn,

    // USB-UART bridge
    output logic        uart_tx,
    input  logic        uart_rx,

    // Board I/O
    output logic [15:0] leds,
    input  logic [15:0] switches,

    // 5 push buttons: [0]=BTNU [1]=BTNL [2]=BTNR [3]=BTND [4]=BTNC
    input  logic [4:0]  buttons,

    // 7-segment display (8-digit, active LOW)
    output logic [7:0]  an,
    output logic [6:0]  seg,
    output logic        dp,

    // SPI flash (on-board N25Q128A Quad-SPI flash, standard SPI mode)
    // CCLK is driven via STARTUPE2 internally — not a top-level port.
    output logic        flash_cs_n,
    output logic        flash_mosi,
    input  logic        flash_miso,
    output logic        flash_wp_n,
    output logic        flash_hold_n,

    // PS/2 keyboard
    input  logic        ps2_clk,
    input  logic        ps2_data,

    // VGA output
    output logic        hsync,
    output logic        vsync,
    output logic [3:0]  vga_r,
    output logic [3:0]  vga_g,
    output logic [3:0]  vga_b
);

    // --------------------------------------------------------
    // Reset synchronizer
    //   - Asynchronous assertion (the moment the button is
    //     pressed the system enters reset).
    //   - Synchronous deassertion through two flops to
    //     prevent metastability when the button is released.
    // --------------------------------------------------------
    logic       rst_async;
    logic [1:0] rst_sync_ff;
    logic       rst_n;

    assign rst_async = ~cpu_rst_btn;  // CPU_RESETN is active-LOW

    always_ff @(posedge clk_100mhz or posedge rst_async) begin
        if (rst_async)
            rst_sync_ff <= 2'b00;
        else
            rst_sync_ff <= {rst_sync_ff[0], 1'b1};
    end

    assign rst_n = rst_sync_ff[1];

    // --------------------------------------------------------
    // SPI wires from SoC
    // --------------------------------------------------------
    logic spi_sck;

    // --------------------------------------------------------
    // STARTUPE2 — routes spi_sck to the CCLK pin.
    // After FPGA configuration CCLK can only be driven via this
    // primitive; a regular I/O output cannot reach it.
    // USRCCLKTS = 0 enables the USRCCLKO path.
    // --------------------------------------------------------
    STARTUPE2 #(
        .PROG_USR     ("FALSE"),
        .SIM_CCLK_FREQ(0.0)
    ) u_startupe2 (
        .CFGCLK   (),
        .CFGMCLK  (),
        .EOS      (),
        .PREQ     (),
        .CLK      (1'b0),
        .GSR      (1'b0),
        .GTS      (1'b0),
        .KEYCLEARB(1'b1),
        .PACK     (1'b0),
        .USRCCLKO (spi_sck),
        .USRCCLKTS(1'b0),
        .USRDONEO (1'b1),
        .USRDONETS(1'b1)
    );

    // --------------------------------------------------------
    // SoC instance
    // --------------------------------------------------------
    soc_top #(
        .IMEM_FILE     ("bootloader.mem"),
        .UART_CLK_FREQ (100_000_000),
        .PC_RESET      (32'h00007800)
    ) u_soc (
        .clk_100mhz  (clk_100mhz),
        .rst_n       (rst_n),
        .uart_tx     (uart_tx),
        .uart_rx     (uart_rx),
        .leds        (leds),
        .switches    (switches),
        .buttons     (buttons),
        .an          (an),
        .seg         (seg),
        .dp          (dp),
        .spi_sck     (spi_sck),
        .spi_cs_n    (flash_cs_n),
        .spi_mosi    (flash_mosi),
        .spi_miso    (flash_miso),
        .spi_wp_n    (flash_wp_n),
        .spi_hold_n  (flash_hold_n),
        .ps2_clk     (ps2_clk),
        .ps2_data    (ps2_data),
        .hsync       (hsync),
        .vsync       (vsync),
        .vga_r       (vga_r),
        .vga_g       (vga_g),
        .vga_b       (vga_b)
    );

endmodule
