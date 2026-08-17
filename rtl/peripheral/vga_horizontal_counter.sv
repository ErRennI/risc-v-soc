module vga_horizontal_counter (
    input logic clk_25mhz,
    rst,
    output logic done_x,
    output logic [9:0] h_cnt
);
    localparam H_TOTAL = 800;
    logic [9:0] pixel_cnt_reg, pixel_cnt_next;


    always_ff @(posedge clk_25mhz, negedge rst) begin
        if (!rst) pixel_cnt_reg <= 10'b0;
        else pixel_cnt_reg <= pixel_cnt_next;
    end

    always_comb begin
        if (pixel_cnt_reg == (H_TOTAL - 1)) begin
            pixel_cnt_next = 10'd0;
        end else begin
            pixel_cnt_next = pixel_cnt_reg + 1'b1;
        end
    end

    assign h_cnt  = pixel_cnt_reg;
    assign done_x = (pixel_cnt_reg == (H_TOTAL - 1));
endmodule
