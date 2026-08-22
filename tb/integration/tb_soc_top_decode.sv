// ============================================================
// Module  : tb_soc_top_decode
// Purpose : Top-level decode and MMIO mux regression
//           Verifies region selection and read-data routing.
// ============================================================

module tb_soc_top_decode;

    // --- Signals ---
    logic        clk_100mhz;
    logic        rst_n;
    logic        uart_tx;
    logic        uart_rx;
    logic [15:0] leds;
    logic [15:0] switches;
    logic [4:0]  buttons;
    logic [7:0]  an;
    logic [6:0]  seg;
    logic        dp;
    int          error_count;

    // --- Instantiate SoC ---
    soc_top #(
        .IMEM_DEPTH (4),
        .IMEM_FILE  ("sw/tests/test_imem.mem")
    ) dut (
        .clk_100mhz (clk_100mhz),
        .rst_n      (rst_n),
        .uart_tx    (uart_tx),
        .uart_rx    (uart_rx),
        .leds       (leds),
        .switches   (switches),
        .buttons    (buttons),
        .an         (an),
        .seg        (seg),
        .dp         (dp),
        .spi_sck    (),
        .spi_cs_n   (),
        .spi_mosi   (),
        .spi_miso   (1'b0),
        .spi_wp_n   (),
        .spi_hold_n ()
    );

    initial clk_100mhz = 1'b0;
    always #5 clk_100mhz = ~clk_100mhz;

    // --- Helper checks ---
    task automatic check_bit(
        input logic actual,
        input logic expected,
        input string name
    );
        begin
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("FAIL: %s expected %0b, got %0b", name, expected, actual);
            end
            else begin
                $display("PASS: %s = %0b", name, actual);
            end
        end
    endtask

    task automatic check_word(
        input logic [31:0] actual,
        input logic [31:0] expected,
        input string name
    );
        begin
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("FAIL: %s expected 0x%08h, got 0x%08h", name, expected, actual);
            end
            else begin
                $display("PASS: %s = 0x%08h", name, actual);
            end
        end
    endtask

    initial begin
        $dumpfile("sim_soc_decode.vcd");
        $dumpvars(0, tb_soc_top_decode);

        error_count = 0;
        rst_n = 1'b0;
        uart_rx = 1'b1;
        switches = 16'h0000;
        buttons = 5'b0;

        @(posedge clk_100mhz);
        @(posedge clk_100mhz);
        rst_n = 1'b1;
        @(posedge clk_100mhz);
        #1;

        // --- Test 1: Peripheral region select ---
        force dut.dmem_addr = 32'h4000_0000;
        #1;
        check_bit(dut.uart_sel,     1'b1, "UART select");
        check_bit(dut.timer_sel,    1'b0, "Timer deselect when UART selected");
        check_bit(dut.gpio_sel,     1'b0, "GPIO deselect when UART selected");
        check_bit(dut.sevenseg_sel, 1'b0, "7-seg deselect when UART selected");

        force dut.dmem_addr = 32'h4000_1000;
        #1;
        check_bit(dut.uart_sel,     1'b0, "UART deselect when timer selected");
        check_bit(dut.timer_sel,    1'b1, "Timer select");
        check_bit(dut.gpio_sel,     1'b0, "GPIO deselect when timer selected");
        check_bit(dut.sevenseg_sel, 1'b0, "7-seg deselect when timer selected");

        force dut.dmem_addr = 32'h4000_2000;
        #1;
        check_bit(dut.uart_sel,     1'b0, "UART deselect when GPIO selected");
        check_bit(dut.timer_sel,    1'b0, "Timer deselect when GPIO selected");
        check_bit(dut.gpio_sel,     1'b1, "GPIO select");
        check_bit(dut.sevenseg_sel, 1'b0, "7-seg deselect when GPIO selected");

        force dut.dmem_addr = 32'h4000_3000;
        #1;
        check_bit(dut.uart_sel,     1'b0, "UART deselect when 7-seg selected");
        check_bit(dut.timer_sel,    1'b0, "Timer deselect when 7-seg selected");
        check_bit(dut.gpio_sel,     1'b0, "GPIO deselect when 7-seg selected");
        check_bit(dut.sevenseg_sel, 1'b1, "7-seg select");

        force dut.dmem_addr = 32'h4000_5000;  // VGA tile VRAM base
        #1;
        check_bit(dut.uart_sel,     1'b0, "UART deselect when VGA selected");
        check_bit(dut.sevenseg_sel, 1'b0, "7-seg deselect when VGA selected");
        check_bit(dut.vga_sel,      1'b1, "VGA select");
        check_bit(dut.kbd_sel,      1'b0, "Keyboard deselect when VGA selected");

        force dut.dmem_addr = 32'h4000_757F;  // last byte of the VGA tile VRAM window
        #1;
        check_bit(dut.vga_sel, 1'b1, "VGA select at top of its window (0x40007580 - 1)");

        force dut.dmem_addr = 32'h4000_7580;  // one past the VGA tile VRAM window
        #1;
        check_bit(dut.vga_sel, 1'b0, "VGA deselect just past its window");

        force dut.dmem_addr = 32'h4000_8000;  // PS/2 keyboard base
        #1;
        check_bit(dut.vga_sel, 1'b0, "VGA deselect when keyboard selected");
        check_bit(dut.kbd_sel, 1'b1, "Keyboard select");

        // --- Test 2: Read-data mux routing ---
        // DMEM path: dmem_read_data_raw is already registered by BRAM; check combinationally.
        force dut.dmem_addr = 32'h2000_0000;
        force dut.dmem_read_data_raw = 32'h1234_5678;
        #1;
        check_word(dut.dmem_read_data, 32'h1234_5678, "DMEM read route");

        // MMIO paths: mmio_read_data_reg is a flip-flop that captures on posedge when
        // dmem_read_en=1. Assert read_en and clock once before sampling.
        force dut.uart_read_data  = 32'hAAAA_0001;
        force dut.timer_read_data = 32'hBBBB_0002;
        force dut.gpio_read_data  = 32'hCCCC_0003;
        force dut.dmem_read_en    = 1'b1;

        force dut.dmem_addr = 32'h4000_0000;
        @(posedge clk_100mhz); #1;
        check_word(dut.dmem_read_data, 32'hAAAA_0001, "UART read mux");

        force dut.dmem_addr = 32'h4000_1000;
        @(posedge clk_100mhz); #1;
        check_word(dut.dmem_read_data, 32'hBBBB_0002, "Timer read mux");

        force dut.dmem_addr = 32'h4000_2000;
        @(posedge clk_100mhz); #1;
        check_word(dut.dmem_read_data, 32'hCCCC_0003, "GPIO read mux");

        force dut.vram_ready    = 1'b0;
        force dut.kbd_ready     = 1'b1;
        force dut.kbd_scan_code = 8'h1C;

        force dut.dmem_addr = 32'h4000_5000;
        @(posedge clk_100mhz); #1;
        check_word(dut.dmem_read_data, 32'h0000_0000, "VGA read mux (vram_ready=0)");

        force dut.dmem_addr = 32'h4000_8000;
        @(posedge clk_100mhz); #1;
        check_word(dut.dmem_read_data, 32'h0000_011C, "Keyboard read mux (ready=1, code=0x1C)");

        release dut.dmem_read_en;
        release dut.dmem_addr;
        release dut.dmem_read_data_raw;
        release dut.uart_read_data;
        release dut.timer_read_data;
        release dut.gpio_read_data;
        release dut.vram_ready;
        release dut.kbd_ready;
        release dut.kbd_scan_code;

        if (error_count != 0) begin
            $display("SoC decode regression failed with %0d error(s).", error_count);
            $fatal(1);
        end

        $display("SoC decode regression passed.");
        $finish;
    end

endmodule
