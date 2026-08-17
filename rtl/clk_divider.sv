module clk_divider (
    input  logic input_clk,
    input  logic rst,
    output logic output_clk
);
    logic [1:0] clk_div;  //Divides by 4

    always_ff @(posedge input_clk, negedge rst) begin
        if (!rst) clk_div <= 2'b00;
        else clk_div <= clk_div + 1'b1;
    end
    assign output_clk = clk_div[1];
endmodule
