// ============================================================
// Module  : tb_calculator
// Purpose : Integration test for the PS/2 keyboard + VGA calculator
//           firmware (sw/tests/calculator.c).
//
//           Types key sequences into soc_top's PS/2 pins exactly like a
//           keyboard (make code, then F0 + break code), and reads the
//           result line straight out of the VGA tile VRAM.
//
//           Each expression: digits of A, Enter x2, operator key,
//           Enter x2, digits of B, Enter x2 -> result on row 28.
//           One extra key (Space) then starts the next calculation.
// ============================================================

module tb_calculator;

    // PS/2 half-period in 100 MHz cycles. Real keyboards run ~10-16 kHz;
    // a faster clock keeps the sim short. The RTL only needs a clean
    // falling edge seen by its 3-sample filter, so anything >> 3 works.
    localparam int PS2_HALF      = 50;
    localparam int KEY_TIMEOUT   = 400_000;   // cycles for CPU to read one byte
    localparam int LINE_TIMEOUT  = 400_000;   // cycles for result to appear
    localparam int RESULT_ROW    = 28;
    localparam int STATUS_ROW    = 25;

    // PS/2 scan code set 2 make codes, as decoded by keyboard.c
    localparam logic [7:0] K_ENTER = 8'h5A;
    localparam logic [7:0] K_BKSP  = 8'h66;
    localparam logic [7:0] K_SPACE = 8'h29;
    localparam logic [7:0] K_A     = 8'h1C;   // add
    localparam logic [7:0] K_S     = 8'h1B;   // subtract
    localparam logic [7:0] K_M     = 8'h3A;   // multiply
    localparam logic [7:0] K_D     = 8'h23;   // divide

    logic        clk_100mhz;
    logic        rst_n;
    logic        ps2_clk;
    logic        ps2_data;

    int error_count;

    soc_top #(
        .IMEM_FILE ("sw/tests/calculator.mem"),
        .PC_RESET  (32'h0000_0000)
    ) dut (
        .clk_100mhz (clk_100mhz),
        .rst_n      (rst_n),
        .uart_tx    (),
        .uart_rx    (1'b1),
        .leds       (),
        .switches   (16'h0),
        .buttons    (5'b0),
        .an         (),
        .seg        (),
        .dp         (),
        .ps2_clk    (ps2_clk),
        .ps2_data   (ps2_data),
        .spi_sck    (),
        .spi_cs_n   (),
        .spi_mosi   (),
        .spi_miso   (1'b0),
        .spi_wp_n   (),
        .spi_hold_n (),
        .hsync      (),
        .vsync      (),
        .vga_r      (),
        .vga_g      (),
        .vga_b      ()
    );

    initial clk_100mhz = 1'b0;
    always #5 clk_100mhz = ~clk_100mhz;

    // ---------------- PS/2 device model ----------------

    // Send one 11-bit frame: start(0), 8 data bits LSB first, odd parity,
    // stop(1). Data changes while the clock is high; the host samples on
    // the falling edge.
    task automatic ps2_send_byte(input logic [7:0] b);
        logic [10:0] frame;
        int i;
        begin
            frame = {1'b1, ~^b, b, 1'b0};
            for (i = 0; i < 11; i++) begin
                ps2_data = frame[i];
                repeat (PS2_HALF) @(posedge clk_100mhz);
                ps2_clk = 1'b0;
                repeat (PS2_HALF) @(posedge clk_100mhz);
                ps2_clk = 1'b1;
            end
            ps2_data = 1'b1;
        end
    endtask

    // The keyboard register holds one byte. Wait until firmware has read
    // it (kbd_ready back to 0) before sending the next, as a real
    // keyboard's ~1 ms byte spacing would allow.
    task automatic wait_byte_consumed(input logic [7:0] b);
        int t;
        begin
            t = 0;
            while (dut.kbd_ready !== 1'b0 && t < KEY_TIMEOUT) begin
                @(posedge clk_100mhz);
                t++;
            end
            if (t >= KEY_TIMEOUT) begin
                error_count++;
                $display("FAIL: firmware never read PS/2 byte 0x%02h", b);
            end
        end
    endtask

    task automatic ps2_byte(input logic [7:0] b);
        begin
            ps2_send_byte(b);
            // kbd_ready rises a cycle or two after the stop bit is sampled
            repeat (4) @(posedge clk_100mhz);
            wait_byte_consumed(b);
        end
    endtask

    // One key tap: make code, then break (F0 + code)
    task automatic tap(input logic [7:0] code);
        begin
            ps2_byte(code);
            ps2_byte(8'hF0);
            ps2_byte(code);
        end
    endtask

    task automatic type_digits(input string s);
        int i;
        begin
            for (i = 0; i < s.len(); i++) tap(digit_code(s[i]));
        end
    endtask

    function automatic logic [7:0] digit_code(input byte c);
        case (c)
            "0": return 8'h45; "1": return 8'h16; "2": return 8'h1E;
            "3": return 8'h26; "4": return 8'h25; "5": return 8'h2E;
            "6": return 8'h36; "7": return 8'h3D; "8": return 8'h3E;
            "9": return 8'h46;
            default: return 8'h00;
        endcase
    endfunction

    // ---------------- VRAM readback ----------------

    function automatic byte tile_char(input int x, input int y);
        logic [15:0] w;
        begin
            w = dut.u_vga_vram.mem[y * 80 + x];
            return w[7:0];
        end
    endfunction

    function automatic logic [3:0] tile_color(input int x, input int y);
        logic [15:0] w;
        begin
            w = dut.u_vga_vram.mem[y * 80 + x];
            return w[11:8];
        end
    endfunction

    // 1 if row y, with leading/trailing blanks trimmed, equals `expected`.
    // (Compared char by char: Icarus can't build strings in functions.)
    function automatic bit row_equals(input int y, input string expected);
        int first, last, x;
        byte c;
        begin
            first = -1; last = -1;
            for (x = 0; x < 80; x++) begin
                c = tile_char(x, y);
                if (c != " " && c != 8'h00) begin
                    if (first < 0) first = x;
                    last = x;
                end
            end
            if (first < 0) return (expected.len() == 0);
            if (last - first + 1 != expected.len()) return 0;
            for (x = first; x <= last; x++)
                if (tile_char(x, y) != expected[x - first]) return 0;
            return 1;
        end
    endfunction

    task automatic print_row(input int y);
        int x;
        begin
            $write("\"");
            for (x = 0; x < 80; x++) $write("%c", tile_char(x, y));
            $write("\"\n");
        end
    endtask

    // Column where `needle` starts on row y, or -1
    function automatic int find_on_row(input int y, input string needle);
        int x, k, hit;
        begin
            for (x = 0; x + needle.len() <= 80; x++) begin
                hit = 1;
                for (k = 0; k < needle.len(); k++)
                    if (tile_char(x + k, y) != needle[k]) hit = 0;
                if (hit) return x;
            end
            return -1;
        end
    endfunction

    task automatic expect_row(input int y, input string expected, input string name);
        int t;
        begin
            t = 0;
            while (!row_equals(y, expected) && t < LINE_TIMEOUT) begin
                repeat (100) @(posedge clk_100mhz);
                t += 100;
            end
            if (row_equals(y, expected)) begin
                $display("PASS: %s -> \"%s\"", name, expected);
            end else begin
                error_count++;
                $display("FAIL: %s expected \"%s\", row %0d is:", name, expected, y);
                print_row(y);
            end
        end
    endtask

    task automatic expect_color(input int y, input string needle, input logic [3:0] color,
                                input string name);
        int x;
        begin
            x = find_on_row(y, needle);
            if (x < 0) begin
                error_count++;
                $display("FAIL: %s: \"%s\" not on row %0d", name, needle, y);
            end else if (tile_color(x, y) !== color) begin
                error_count++;
                $display("FAIL: %s color expected 0x%01h, got 0x%01h", name, color, tile_color(x, y));
            end else begin
                $display("PASS: %s color = 0x%01h", name, color);
            end
        end
    endtask

    // Full expression: A, op, B, each confirmed with Enter twice
    task automatic calc(input string a, input logic [7:0] op_key, input string b);
        begin
            type_digits(a);
            tap(K_ENTER); tap(K_ENTER);
            tap(op_key);
            tap(K_ENTER); tap(K_ENTER);
            type_digits(b);
            tap(K_ENTER); tap(K_ENTER);
        end
    endtask

    // ---------------- Test sequence ----------------

    initial begin
        $dumpfile("sim_calculator.vcd");
        $dumpvars(0, tb_calculator);

        error_count = 0;
        ps2_clk  = 1'b1;
        ps2_data = 1'b1;
        rst_n    = 1'b0;
        repeat (10) @(posedge clk_100mhz);
        rst_n = 1'b1;

        // Boot: screen clear + controls legend on row 1 + idle status
        expect_row(1, "0-9:digits  A:+ S:- M:* D:/  Enter:confirm(x2)  Backspace:edit/back",
                   "legend on row 1");

        // First key also draws the initial status line
        tap(K_SPACE);
        expect_row(STATUS_ROW,
                   "Enter operand A (0-9) - Enter to confirm, Backspace to edit",
                   "status: enter A");

        // --- ADD ---
        calc("12", K_A, "3");
        expect_row(RESULT_ROW, "12 + 3 = 15", "ADD");
        expect_color(RESULT_ROW, "+", 4'hE, "ADD operator");
        expect_color(RESULT_ROW, "15", 4'h2, "ADD result");
        expect_row(STATUS_ROW,
                   "Result shown below - press any key to start a new calculation",
                   "status: result");
        tap(K_SPACE);

        // --- MUL ---
        calc("7", K_M, "6");
        expect_row(RESULT_ROW, "7 * 6 = 42", "MUL");
        tap(K_SPACE);

        // --- SUB ---
        calc("9", K_S, "4");
        expect_row(RESULT_ROW, "9 - 4 = 5", "SUB");
        tap(K_SPACE);

        // --- SUB below zero is reported as OVERFLOW (unsigned math) ---
        calc("3", K_S, "5");
        expect_row(RESULT_ROW, "3 - 5 = OVERFLOW", "SUB underflow");
        expect_color(RESULT_ROW, "OVERFLOW", 4'hC, "OVERFLOW");
        tap(K_SPACE);

        // --- DIV ---
        calc("20", K_D, "3");
        expect_row(RESULT_ROW, "20 / 3 = 6", "DIV");
        tap(K_SPACE);

        // --- DIV by zero ---
        calc("8", K_D, "0");
        expect_row(RESULT_ROW, "8 / 0 = DIV BY ZERO", "DIV/0");
        tap(K_SPACE);

        // --- Backspace editing: type 19, delete the 9, type 2 -> 12 ---
        type_digits("19");
        tap(K_BKSP);
        type_digits("2");
        expect_row(RESULT_ROW, "12", "backspace edits operand A");
        tap(K_ENTER); tap(K_ENTER);
        tap(K_A);
        expect_row(RESULT_ROW, "12 + 0", "operator shows B placeholder");
        tap(K_ENTER); tap(K_ENTER);
        type_digits("8");
        tap(K_ENTER); tap(K_ENTER);
        expect_row(RESULT_ROW, "12 + 8 = 20", "ADD after backspace");

        if (error_count != 0) begin
            $display("Calculator integration test failed with %0d error(s).", error_count);
            $fatal(1);
        end

        $display("PASS: calculator integration test passed");
        $finish;
    end

    // Global watchdog
    initial begin
        #200_000_000;
        $display("FAIL: global timeout");
        $fatal(1);
    end

endmodule
