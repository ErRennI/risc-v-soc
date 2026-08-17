module font_rom (
    input logic clk_25mhz,
    input logic [10:0] rom_addr,
    output logic [7:0] rom_data
);

    logic [7:0] mem[0:2047];

    
    initial begin
`ifdef SYNTHESIS
        $readmemh("font_data.mem", mem);
`else
        $readmemh("rtl/font_data.mem", mem);
`endif
    end

    always_ff @(posedge clk_25mhz) begin
        rom_data <= mem[rom_addr];
    end
endmodule
