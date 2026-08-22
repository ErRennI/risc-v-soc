// ============================================================
// Module  : tb_vga_core
// Purpose : Testbench for the tile lookup and glyph/color
//           rendering logic in rtl/peripheral/vga_core.sv.
//           Exercises vga_address_translator (pixel->tile index)
//           and vga_pixel_gen (font bit + color palette -> RGB)
//           directly, since both are pure combinational logic.
// ============================================================

module tb_vga_core;

    int error_count;

    task automatic check_word(input logic [31:0] actual, input logic [31:0] expected, input string name);
        begin
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("FAIL: %s expected %0d, got %0d", name, expected, actual);
            end else begin
                $display("PASS: %s = %0d", name, actual);
            end
        end
    endtask

    task automatic check_nibble(input logic [3:0] actual, input logic [3:0] expected, input string name);
        begin
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("FAIL: %s expected 0x%01h, got 0x%01h", name, expected, actual);
            end else begin
                $display("PASS: %s = 0x%01h", name, actual);
            end
        end
    endtask

    // ============================================================
    // vga_address_translator: pixel coordinates -> tile VRAM index
    // 80 columns x 60 rows of 8x8 tiles.
    // ============================================================
    logic [9:0]  at_pixel_x, at_pixel_y;
    logic [12:0] at_vga_read_addr;

    vga_address_translator u_addr_translator (
        .pixel_x      (at_pixel_x),
        .pixel_y      (at_pixel_y),
        .vga_read_addr(at_vga_read_addr)
    );

    // ============================================================
    // vga_pixel_gen: font bit + color nibble -> RGB nibbles
    // ============================================================
    logic       pg_video_on;
    logic [9:0] pg_pixel_x, pg_pixel_y;
    logic [7:0] pg_char_code;
    logic [7:0] pg_font_word;
    logic [3:0] pg_char_color;
    logic [3:0] pg_vga_r, pg_vga_g, pg_vga_b;

    vga_pixel_gen u_pixel_gen (
        .video_on  (pg_video_on),
        .pixel_x   (pg_pixel_x),
        .pixel_y   (pg_pixel_y),
        .char_code (pg_char_code),
        .font_word (pg_font_word),
        .char_color(pg_char_color),
        .vga_r     (pg_vga_r),
        .vga_g     (pg_vga_g),
        .vga_b     (pg_vga_b)
    );

    initial begin
        $dumpfile("sim_vga_core.vcd");
        $dumpvars(0, tb_vga_core);

        error_count = 0;

        // --- Test 1: Address translator — origin tile ---
        at_pixel_x = 10'd0;
        at_pixel_y = 10'd0;
        #1;
        check_word(at_vga_read_addr, 13'd0, "tile addr at (0,0)");

        // --- Test 2: Still inside tile 0 (last pixel column before tile 1) ---
        at_pixel_x = 10'd7;
        at_pixel_y = 10'd0;
        #1;
        check_word(at_vga_read_addr, 13'd0, "tile addr at (7,0) still tile 0");

        // --- Test 3: First pixel of the next tile column ---
        at_pixel_x = 10'd8;
        at_pixel_y = 10'd0;
        #1;
        check_word(at_vga_read_addr, 13'd1, "tile addr at (8,0) = tile 1");

        // --- Test 4: First pixel of the second tile row (row stride = 80) ---
        at_pixel_x = 10'd0;
        at_pixel_y = 10'd8;
        #1;
        check_word(at_vga_read_addr, 13'd80, "tile addr at (0,8) = tile 80");

        // --- Test 5: Arbitrary mid-tile pixel (column 100 -> tile 12, row 16 -> tile row 2) ---
        at_pixel_x = 10'd100;  // tile_x = 100/8 = 12
        at_pixel_y = 10'd16;   // tile_y = 16/8 = 2
        #1;
        check_word(at_vga_read_addr, 13'(2 * 80 + 12), "tile addr at (100,16) = tile 172");

        // --- Test 6: Last visible pixel (639,479) -> last tile (79,59) -> index 4799 ---
        at_pixel_x = 10'd639;
        at_pixel_y = 10'd479;
        #1;
        check_word(at_vga_read_addr, 13'd4799, "tile addr at (639,479) = last tile 4799");

        // --- Test 7: Pixel generator — video off forces black regardless of font/color ---
        pg_video_on   = 1'b0;
        pg_pixel_x    = 10'd0;
        pg_pixel_y    = 10'd0;
        pg_char_code  = 8'h41;
        pg_font_word  = 8'hFF;
        pg_char_color = 4'hF;
        #1;
        check_nibble(pg_vga_r, 4'h0, "vga_r black when video_on=0");
        check_nibble(pg_vga_g, 4'h0, "vga_g black when video_on=0");
        check_nibble(pg_vga_b, 4'h0, "vga_b black when video_on=0");

        // --- Test 8: video_on=1, font bit clear -> black regardless of color ---
        pg_video_on   = 1'b1;
        pg_pixel_x    = 10'd0;   // bit_addr = 0 -> tests font_word[7]
        pg_font_word  = 8'b0000_0000;
        pg_char_color = 4'hF;    // white, but should not show through
        #1;
        check_nibble(pg_vga_r, 4'h0, "vga_r black when font bit clear");
        check_nibble(pg_vga_g, 4'h0, "vga_g black when font bit clear");
        check_nibble(pg_vga_b, 4'h0, "vga_b black when font bit clear");

        // --- Test 9: video_on=1, font bit set at bit_addr=0 (font_word[7]), color=white ---
        pg_font_word  = 8'b1000_0000;
        pg_char_color = 4'hF;  // White -> r=g=b=0xF
        #1;
        check_nibble(pg_vga_r, 4'hF, "vga_r white glyph pixel");
        check_nibble(pg_vga_g, 4'hF, "vga_g white glyph pixel");
        check_nibble(pg_vga_b, 4'hF, "vga_b white glyph pixel");

        // --- Test 10: color palette — dark red (0x4) -> r=0xA g=0x0 b=0x0 ---
        pg_char_color = 4'h4;
        #1;
        check_nibble(pg_vga_r, 4'hA, "vga_r dark red glyph pixel");
        check_nibble(pg_vga_g, 4'h0, "vga_g dark red glyph pixel");
        check_nibble(pg_vga_b, 4'h0, "vga_b dark red glyph pixel");

        // --- Test 11: color palette — light cyan (0xB) -> r=0x5 g=0xF b=0xF ---
        pg_char_color = 4'hB;
        #1;
        check_nibble(pg_vga_r, 4'h5, "vga_r light cyan glyph pixel");
        check_nibble(pg_vga_g, 4'hF, "vga_g light cyan glyph pixel");
        check_nibble(pg_vga_b, 4'hF, "vga_b light cyan glyph pixel");

        // --- Test 12: bit_addr indexing — pixel_x[2:0]=3 selects font_word[4] ---
        pg_pixel_x    = 10'd3;
        pg_font_word  = 8'b0001_0000;  // bit 4 set
        pg_char_color = 4'hF;
        #1;
        check_nibble(pg_vga_r, 4'hF, "vga_r bit_addr=3 selects font_word[4] set");

        pg_pixel_x = 10'd2;  // bit_addr=2 -> font_word[5], which is 0 here
        #1;
        check_nibble(pg_vga_r, 4'h0, "vga_r bit_addr=2 selects font_word[5] clear");

        if (error_count != 0) begin
            $display("VGA core regression failed with %0d error(s).", error_count);
            $fatal(1);
        end

        $display("All VGA core tests completed.");
        $finish;
    end

endmodule
