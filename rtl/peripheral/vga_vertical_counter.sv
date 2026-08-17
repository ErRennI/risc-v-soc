module vga_vertical_counter (
    input logic clk_25mhz,
    input logic rst,
    input logic done_x,
    output logic done_y,
    output logic [9:0] v_cnt
);
    localparam V_TOTAL = 525;
    logic [9:0] pixel_cnt_reg, pixel_cnt_next;

    always_ff @(posedge clk_25mhz, negedge rst) begin
        if (!rst) pixel_cnt_reg <= 10'b0;
        else pixel_cnt_reg <= pixel_cnt_next;
    end

    always_comb begin
        pixel_cnt_next = pixel_cnt_reg;

        if (done_x) begin
            if (pixel_cnt_reg == (V_TOTAL - 1)) pixel_cnt_next = 10'b0;
            else pixel_cnt_next = pixel_cnt_reg + 1'b1;
        end
    end

    assign v_cnt  = pixel_cnt_reg;
    assign done_y = (done_x && (pixel_cnt_reg == (V_TOTAL - 1)));
endmodule
