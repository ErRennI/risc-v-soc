module vga_address_translator(
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
