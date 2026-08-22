// ============================================================
// Module  : tb_vga_sync
// Purpose : Testbench for VGA sync generator (640x480 timing)
//           Verifies horizontal/vertical counter wraparound,
//           video_on visible-window gating, and hsync/vsync
//           pulse timing at region boundaries.
// ============================================================

module tb_vga_sync;

    // --- Signals ---
    logic       clk_25mhz;
    logic       rst;
    logic       hsync;
    logic       vsync;
    logic       video_on;
    logic [9:0] pixel_x;
    logic [9:0] pixel_y;

    // --- Timing constants (must mirror rtl/peripheral/vga_sync.sv) ---
    localparam int H_VISIBLE     = 640;
    localparam int H_FRONT_PORCH = 16;
    localparam int H_SYNC_PULSE  = 96;
    localparam int H_TOTAL       = 800;

    localparam int V_VISIBLE    = 480;
    localparam int V_SYNC_START = V_VISIBLE + 10;    // 490: front porch ends
    localparam int V_SYNC_END   = V_SYNC_START + 2;  // 492: sync pulse ends
    localparam int V_TOTAL      = 525;

    int cyc_count;
    int error_count;

    // --- Instantiate vga_sync ---
    vga_sync dut (
        .clk_25mhz (clk_25mhz),
        .rst       (rst),
        .hsync     (hsync),
        .vsync     (vsync),
        .video_on  (video_on),
        .pixel_x   (pixel_x),
        .pixel_y   (pixel_y)
    );

    // --- Clock generator ---
    initial clk_25mhz = 0;
    always #5 clk_25mhz = ~clk_25mhz;

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

    // Advance the free-running counter to an absolute (v,h) position,
    // relative to cyc_count cycles elapsed since reset release.
    task automatic advance_to(input int target_v, input int target_h);
        int target_cyc;
        int delta;
        begin
            target_cyc = target_v * H_TOTAL + target_h;
            delta = target_cyc - cyc_count;
            if (delta > 0) begin
                repeat (delta) @(posedge clk_25mhz);
                cyc_count = cyc_count + delta;
            end
            #1;
        end
    endtask

    initial begin
        $dumpfile("sim_vga_sync.vcd");
        $dumpvars(0, tb_vga_sync);

        error_count = 0;
        rst = 0;

        @(posedge clk_25mhz);
        #1;
        @(posedge clk_25mhz);
        #1;

        rst = 1;
        #1;
        cyc_count = 0;

        // --- Test 1: Reset state ---
        check_bit(pixel_x == 10'd0, 1'b1, "pixel_x = 0 after reset");
        check_bit(pixel_y == 10'd0, 1'b1, "pixel_y = 0 after reset");
        check_bit(video_on, 1'b1, "video_on at (0,0)");
        check_bit(hsync, 1'b1, "hsync high at (0,0)");
        check_bit(vsync, 1'b1, "vsync high at (0,0)");

        // --- Test 2: Horizontal visible/porch/sync boundaries (row 0) ---
        advance_to(0, H_VISIBLE - 1);  // last visible pixel
        check_bit(video_on, 1'b1, "video_on at last visible column (639)");

        advance_to(0, H_VISIBLE);  // front porch starts
        check_bit(video_on, 1'b0, "video_on off at front porch start (640)");
        check_bit(hsync, 1'b1, "hsync still high in front porch (640)");

        advance_to(0, H_VISIBLE + H_FRONT_PORCH - 1);  // last front-porch cycle
        check_bit(hsync, 1'b1, "hsync high at end of front porch (655)");

        advance_to(0, H_VISIBLE + H_FRONT_PORCH);  // sync pulse starts
        check_bit(hsync, 1'b0, "hsync low at sync pulse start (656)");

        advance_to(0, H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE - 1);  // last sync cycle
        check_bit(hsync, 1'b0, "hsync low at end of sync pulse (751)");

        advance_to(0, H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE);  // back porch starts
        check_bit(hsync, 1'b1, "hsync high at back porch start (752)");

        advance_to(0, H_TOTAL - 1);  // last cycle of row 0
        check_bit(hsync, 1'b1, "hsync high at end of row (799)");

        // --- Test 3: Horizontal wraparound advances pixel_y ---
        repeat (1) @(posedge clk_25mhz);
        cyc_count = cyc_count + 1;
        #1;
        check_bit(pixel_x == 10'd0, 1'b1, "pixel_x wraps to 0 after row 0");
        check_bit(pixel_y == 10'd1, 1'b1, "pixel_y increments to 1 after row 0");

        // --- Test 4: Vertical visible/porch/sync boundaries ---
        advance_to(V_VISIBLE - 1, 0);  // last visible row, column 0
        check_bit(video_on, 1'b1, "video_on on last visible row (479)");
        check_bit(vsync, 1'b1, "vsync high on last visible row (479)");

        advance_to(V_VISIBLE, 0);  // front porch row starts
        check_bit(video_on, 1'b0, "video_on off at vertical front porch start (480)");
        check_bit(vsync, 1'b1, "vsync still high at vertical front porch start (480)");

        advance_to(V_SYNC_START - 1, 0);  // last front-porch row
        check_bit(vsync, 1'b1, "vsync high at end of vertical front porch (489)");

        advance_to(V_SYNC_START, 0);  // vsync pulse starts
        check_bit(vsync, 1'b0, "vsync low at vertical sync pulse start (490)");

        advance_to(V_SYNC_END - 1, 0);  // last vsync-pulse row
        check_bit(vsync, 1'b0, "vsync low at end of vertical sync pulse (491)");

        advance_to(V_SYNC_END, 0);  // back porch starts
        check_bit(vsync, 1'b1, "vsync high at vertical back porch start (492)");

        advance_to(V_TOTAL - 1, H_TOTAL - 1);  // last cycle of the frame
        check_bit(vsync, 1'b1, "vsync high at last cycle of frame (524,799)");

        // --- Test 5: Full-frame wraparound ---
        repeat (1) @(posedge clk_25mhz);
        cyc_count = cyc_count + 1;
        #1;
        check_bit(pixel_x == 10'd0, 1'b1, "pixel_x wraps to 0 after full frame");
        check_bit(pixel_y == 10'd0, 1'b1, "pixel_y wraps to 0 after full frame");
        check_bit(video_on, 1'b1, "video_on resumes at start of next frame");

        if (error_count != 0) begin
            $display("VGA sync regression failed with %0d error(s).", error_count);
            $fatal(1);
        end

        $display("All VGA sync tests completed.");
        $finish;
    end

endmodule
