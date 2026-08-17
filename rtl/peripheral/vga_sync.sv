module vga_sync (
    input logic clk_25mhz,
    input logic rst,
    output logic hsync,
    output logic vsync,
    output logic video_on,
    output logic [9:0] pixel_x,
    output logic [9:0] pixel_y
);

    logic done_x, done_y;
    logic [9:0] h_cnt, v_cnt;

    localparam H_VISIBLE = 640;
    localparam H_FRONT_PORCH = 16;
    localparam H_SYNC_PULSE = 96;
    localparam H_BACK_PORCH = 48;

    localparam V_VISIBLE = 480;
    localparam V_FRONT_PORCH = 10;
    localparam V_SYNC_PULSE = 2;
    localparam V_BACK_PORCH = 33;

    vga_horizontal_counter h_counter (
        .clk_25mhz(clk_25mhz),
        .rst(rst),
        .done_x(done_x),
        .h_cnt(h_cnt)
    );

    vga_vertical_counter v_counter (
        .clk_25mhz(clk_25mhz),
        .rst(rst),
        .done_x(done_x),
        .done_y(done_y),
        .v_cnt(v_cnt)
    );

    assign hsync = (h_cnt >= (H_VISIBLE + H_FRONT_PORCH) && h_cnt < (H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE)) ? 1'b0 : 1'b1;
    assign vsync = (v_cnt >= (V_VISIBLE + V_FRONT_PORCH) && v_cnt < (V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE)) ? 1'b0 : 1'b1;

    assign video_on = (h_cnt < H_VISIBLE && v_cnt < V_VISIBLE) ? 1'b1 : 1'b0;

    assign pixel_x = h_cnt;
    assign pixel_y = v_cnt;

endmodule
