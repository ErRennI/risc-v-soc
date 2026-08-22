// ============================================================
// Module  : vga_address_translator, vga_pixel_gen, vga_core
// Purpose : 80x60 text-mode tile lookup and glyph/color rendering
//           for the VGA output pipeline. vga_core wires the sync
//           generator, VRAM tile lookup, font ROM, and pixel
//           generator together.
// ============================================================

module vga_address_translator (
    input logic [9:0] pixel_x, pixel_y,
    output logic [12:0] vga_read_addr
    );

    //===============================
    // 640/8 = 80 coloumns 480/8 = 60 rows
    //===============================
    logic [6:0] tile_x;
    logic [5:0] tile_y;

    assign tile_x = pixel_x[9:3];
    assign tile_y = pixel_y[9:3];

    assign vga_read_addr = (13'(tile_y) << 6) + (13'(tile_y) << 4) + 13'(tile_x);
endmodule

module vga_pixel_gen (
    input logic video_on,
    input logic [9:0] pixel_x,
    input logic [9:0] pixel_y,
    input logic [7:0] char_code,
    input logic [7:0] font_word,
    input logic [3:0] char_color,
    output logic [3:0] vga_r,
    output logic [3:0] vga_b,
    output logic [3:0] vga_g
);

    logic [2:0] bit_addr;
    assign bit_addr = pixel_x[2:0];

    logic pixel_bit;
    assign pixel_bit = font_word[3'd7-bit_addr];

    logic [3:0] r_val, g_val, b_val;

    always_comb begin
        case (char_color)
            4'h0: begin  //Black
                r_val = 4'h0;
                b_val = 4'h0;
                g_val = 4'h0;
            end
            4'h1: begin  //Dark Blue
                r_val = 4'h0;
                g_val = 4'h0;
                b_val = 4'hA;
            end
            4'h2: begin  //Dark Green
                r_val = 4'h0;
                g_val = 4'hA;
                b_val = 4'h0;
            end
            4'h3: begin  //Cyan
                r_val = 4'h0;
                g_val = 4'hA;
                b_val = 4'hA;
            end
            4'h4: begin  //Dark Red
                r_val = 4'hA;
                g_val = 4'h0;
                b_val = 4'h0;
            end
            4'h5: begin  //Magenta
                r_val = 4'hA;
                g_val = 4'h0;
                b_val = 4'hA;
            end
            4'h6: begin  //Brown
                r_val = 4'hA;
                g_val = 4'h5;
                b_val = 4'h0;
            end
            4'h7: begin  //Light Grey
                r_val = 4'hA;
                g_val = 4'hA;
                b_val = 4'hA;
            end
            4'h8: begin  //Dark Grey
                r_val = 4'h5;
                g_val = 4'h5;
                b_val = 4'h5;
            end
            4'h9: begin  //Light Blue
                r_val = 4'h5;
                g_val = 4'h5;
                b_val = 4'hF;
            end
            4'hA: begin  //Light Green
                r_val = 4'h5;
                g_val = 4'hF;
                b_val = 4'h5;
            end
            4'hB: begin  //Light Cyan
                r_val = 4'h5;
                g_val = 4'hF;
                b_val = 4'hF;
            end
            4'hC: begin  //Light Red
                r_val = 4'hF;
                g_val = 4'h5;
                b_val = 4'h5;
            end
            4'hD: begin  //Pink
                r_val = 4'hF;
                g_val = 4'h5;
                b_val = 4'hF;
            end
            4'hE: begin  //Yellow
                r_val = 4'hF;
                g_val = 4'hF;
                b_val = 4'h5;
            end
            4'hF: begin  //White
                r_val = 4'hF;
                g_val = 4'hF;
                b_val = 4'hF;
            end
            default: begin  //Default Black
                r_val = 4'h0;
                g_val = 4'h0;
                b_val = 4'h0;
            end
        endcase
    end

    always_comb begin
        vga_r = 0;
        vga_g = 0;
        vga_b = 0;

        if (video_on) begin
            if (pixel_bit) begin
                vga_r = r_val;
                vga_b = b_val;
                vga_g = g_val;
            end else begin
                vga_r = 4'h0;
                vga_g = 4'h0;
                vga_b = 4'h0;
            end
        end
    end

endmodule

module vga_core (
    input logic clk_25mhz,
    input logic rst,

    output logic [12:0] vga_read_addr,
    input  logic [ 7:0] char_code,
    input  logic [ 3:0] char_color,
    input  logic [ 3:0] char_attrib,

    output logic hsync,
    output logic vsync,
    output logic [3:0] vga_r,
    output logic [3:0] vga_g,
    output logic [3:0] vga_b
);


    logic video_on;
    logic [9:0] pixel_x, pixel_y;
    logic [7:0] font_word;

    vga_sync sync_unit (
        .clk_25mhz(clk_25mhz),
        .rst(rst),
        .hsync(hsync),
        .vsync(vsync),
        .video_on(video_on),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y)
    );

    vga_address_translator adress_translator (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .vga_read_addr(vga_read_addr)
    );

    //2-Cycle pipeline because of cycle delay problems
    logic [9:0] pixel_x_c1, pixel_x_c2;
    logic [9:0] pixel_y_c1, pixel_y_c2;
    logic video_on_c1, video_on_c2;

    logic [3:0] char_color_c1;

    always_ff @(posedge clk_25mhz or negedge rst) begin
        if (!rst) begin
            pixel_x_c1    <= 10'd0;
            pixel_x_c2    <= 10'd0;
            pixel_y_c1    <= 10'd0;
            pixel_y_c2    <= 10'd0;
            video_on_c1   <= 1'b0;
            video_on_c2   <= 1'b0;
            char_color_c1 <= 4'd0;
        end else begin
            // Waits VRAM cycle
            pixel_x_c1  <= pixel_x;
            pixel_y_c1  <= pixel_y;
            video_on_c1 <= video_on;
            // Waits ROM cycle
            pixel_x_c2    <= pixel_x_c1;
            pixel_y_c2    <= pixel_y_c1;
            video_on_c2   <= video_on_c1;
            char_color_c1 <= char_color;
        end
    end

    font_rom u_font_rom (
        .clk_25mhz(clk_25mhz),
        .rom_addr ({char_code, pixel_y_c1[2:0]}),
        .rom_data (font_word)
    );


    vga_pixel_gen pixel_unit (
        .video_on(video_on_c2),
        .pixel_x(pixel_x_c2),
        .pixel_y(pixel_y_c2),
        .char_code(char_code),
        .char_color(char_color_c1),
        .font_word(font_word),
        //If ı want ı can add char attributes
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b)
    );

endmodule
