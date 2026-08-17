module ps2_keyboard (
    input logic clk_100mhz,
    input logic rst,

    //physical pins from the keyboard
    input logic ps2_clk,
    input logic ps2_data,

    input logic kbd_read_en,
    output logic [7:0] button_code,
    output logic kbd_ready
);

    logic [2:0] clk_filter_reg;
    logic falling_edge;

    always_ff @(posedge clk_100mhz or negedge rst) begin
        if (!rst) begin
            clk_filter_reg <= 3'b111;
        end else begin
            clk_filter_reg <= {clk_filter_reg[1:0], ps2_clk};
        end
    end

    assign falling_edge = (clk_filter_reg == 3'b100);

    logic [1:0] ps2_data_sync;

    always_ff @(posedge clk_100mhz or negedge rst) begin
        if (!rst) ps2_data_sync <= 2'b11;
        else      ps2_data_sync <= {ps2_data_sync[0], ps2_data};
    end

    logic [ 3:0] bit_cnt_reg;
    logic [10:0] shift_reg;
    logic [ 7:0] scan_code_reg;
    logic        kbd_ready_reg;

    always_ff @(posedge clk_100mhz or negedge rst) begin
        if (!rst) begin
            bit_cnt_reg   <= 4'd0;
            shift_reg     <= 11'd0;
            scan_code_reg <= 8'd0;
            kbd_ready_reg <= 1'b0;
        end else begin
            if (kbd_read_en) begin
                kbd_ready_reg <= 1'b0;
            end
            if (falling_edge) begin
                shift_reg <= {ps2_data_sync[1], shift_reg[10:1]};

                if (bit_cnt_reg == 4'd10) begin
                    bit_cnt_reg <= 4'd0;
                    
                    if (shift_reg[1] == 1'b0) begin
                        scan_code_reg <= shift_reg[9:2];
                        kbd_ready_reg <= 1'b1;
                    end
                end else begin
                    bit_cnt_reg <= bit_cnt_reg + 1'b1;
                end
            end

        end
    end

    assign button_code = scan_code_reg;
    assign kbd_ready   = kbd_ready_reg;

endmodule
