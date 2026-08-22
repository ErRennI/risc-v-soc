// ============================================================
// Module  : tb_vga_vram_ctrl
// Purpose : Testbench for the VGA tile VRAM controller.
//           Verifies CPU write / VGA-side read (dual clock
//           domains), the full-screen clear FSM, and that a
//           CPU write is ignored while a clear is in progress.
// ============================================================

module tb_vga_vram_ctrl;

    // --- Signals ---
    logic        clk_100mhz;
    logic        clk_25mhz;
    logic        rst_n;

    logic        vram_write_en;
    logic        vram_clear_en;
    logic [12:0] cpu_addr;
    logic [15:0] cpu_write_data;
    logic        vram_ready;

    logic [12:0] vga_read_addr;
    logic [ 7:0] char_code;
    logic [ 3:0] char_color;
    logic [ 3:0] char_attrib;

    int error_count;

    localparam int NUM_TILES = 4800;

    // --- Derive clk_25mhz from clk_100mhz the same way soc_top.sv does ---
    clk_divider u_clk_div (
        .input_clk (clk_100mhz),
        .rst       (rst_n),
        .output_clk(clk_25mhz)
    );

    // --- Instantiate vga_vram_ctrl ---
    vga_vram_ctrl dut (
        .clk_100mhz    (clk_100mhz),
        .clk_25mhz     (clk_25mhz),
        .rst           (rst_n),

        .vram_write_en (vram_write_en),
        .vram_clear_en (vram_clear_en),
        .cpu_addr      (cpu_addr),
        .cpu_write_data(cpu_write_data),
        .vram_ready    (vram_ready),

        .vga_read_addr (vga_read_addr),
        .char_code     (char_code),
        .char_color    (char_color),
        .char_attrib   (char_attrib)
    );

    // --- Clock generator ---
    initial clk_100mhz = 0;
    always #5 clk_100mhz = ~clk_100mhz;

    task automatic check_nibble(input logic [3:0] actual, input logic [3:0] expected, input string name);
        begin
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("FAIL: %s expected 0x%01h, got 0x%01h", name, expected, actual);
            end else begin
                $display("PASS: %s = 0x%01h", name, actual);
            end
        end
    endtask

    task automatic check_byte(input logic [7:0] actual, input logic [7:0] expected, input string name);
        begin
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("FAIL: %s expected 0x%02h, got 0x%02h", name, expected, actual);
            end else begin
                $display("PASS: %s = 0x%02h", name, actual);
            end
        end
    endtask

    task automatic check_bit(input logic actual, input logic expected, input string name);
        begin
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("FAIL: %s expected %0b, got %0b", name, expected, actual);
            end else begin
                $display("PASS: %s = %0b", name, actual);
            end
        end
    endtask

    // Read one tile through the registered clk_25mhz read port.
    task automatic read_tile(input logic [12:0] addr);
        begin
            vga_read_addr = addr;
            @(posedge clk_25mhz);
            @(posedge clk_25mhz);
            #1;
        end
    endtask

    initial begin
        $dumpfile("sim_vga_vram_ctrl.vcd");
        $dumpvars(0, tb_vga_vram_ctrl);

        error_count    = 0;
        rst_n          = 0;
        vram_write_en  = 0;
        vram_clear_en  = 0;
        cpu_addr       = 13'd0;
        cpu_write_data = 16'd0;
        vga_read_addr  = 13'd0;

        repeat (4) @(posedge clk_100mhz);
        #1;
        rst_n = 1;
        repeat (2) @(posedge clk_100mhz);
        #1;

        // --- Test 1: Idle state is ready ---
        check_bit(vram_ready, 1'b1, "vram_ready idle before any write");

        // --- Test 2: CPU write then VGA-side read of the same tile ---
        // data[15:12]=attrib=0xA, data[11:8]=color=0x1, data[7:0]=code='A' (0x41)
        vram_write_en  = 1'b1;
        cpu_addr       = 13'd0;
        cpu_write_data = 16'hA141;
        @(posedge clk_100mhz);
        #1;
        vram_write_en = 1'b0;

        read_tile(13'd0);
        check_byte(char_code, 8'h41, "char_code at tile 0 after write");
        check_nibble(char_color, 4'h1, "char_color at tile 0 after write");
        check_nibble(char_attrib, 4'hA, "char_attrib at tile 0 after write");

        // --- Test 3: Second tile is unaffected ---
        read_tile(13'd1);
        check_byte(char_code, 8'h00, "char_code at untouched tile 1");

        // --- Test 4: Full-screen clear FSM ---
        vram_clear_en = 1'b1;
        @(posedge clk_100mhz);
        #1;
        vram_clear_en = 1'b0;

        // Give the FSM a cycle to leave IDLE, then confirm ready drops.
        @(posedge clk_100mhz);
        #1;
        check_bit(vram_ready, 1'b0, "vram_ready low during clear");

        // While clearing, attempt a CPU write — it must be ignored (clear has priority).
        vram_write_en  = 1'b1;
        cpu_addr       = 13'd100;
        cpu_write_data = 16'hFFFF;

        // Wait long enough for all NUM_TILES clear cycles plus the IDLE transition.
        repeat (NUM_TILES + 10) @(posedge clk_100mhz);
        #1;
        vram_write_en = 1'b0;

        check_bit(vram_ready, 1'b1, "vram_ready high after clear completes");

        read_tile(13'd0);
        check_byte(char_code, 8'h20, "char_code at tile 0 after clear (space)");
        check_nibble(char_color, 4'h0, "char_color at tile 0 after clear");
        check_nibble(char_attrib, 4'h0, "char_attrib at tile 0 after clear");

        read_tile(13'(NUM_TILES - 1));
        check_byte(char_code, 8'h20, "char_code at last tile after clear (space)");

        // The write attempted during the clear must have been dropped.
        read_tile(13'd100);
        check_byte(char_code, 8'h20, "char_code at tile 100: clear wins over concurrent write");

        // --- Test 5: A normal write after the clear completes takes effect ---
        vram_write_en  = 1'b1;
        cpu_addr       = 13'd100;
        cpu_write_data = 16'h0342;  // attrib=0, color=3, code=0x42 ('B')
        @(posedge clk_100mhz);
        #1;
        vram_write_en = 1'b0;

        read_tile(13'd100);
        check_byte(char_code, 8'h42, "char_code at tile 100 after post-clear write");
        check_nibble(char_color, 4'h3, "char_color at tile 100 after post-clear write");

        if (error_count != 0) begin
            $display("VGA VRAM controller regression failed with %0d error(s).", error_count);
            $fatal(1);
        end

        $display("All VGA VRAM controller tests completed.");
        $finish;
    end

endmodule
