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
