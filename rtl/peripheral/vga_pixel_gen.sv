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
