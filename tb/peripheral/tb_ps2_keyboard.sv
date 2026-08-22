// ============================================================
// Module  : tb_ps2_keyboard
// Purpose : Testbench for PS/2 keyboard receiver
//           Drives a simulated PS/2 device (start/8 data/parity/stop
//           frame) and checks scan-code capture, kbd_ready latch/clear,
//           and reset behavior.
// ============================================================

module tb_ps2_keyboard;

    // --- Signals ---
    logic       clk_100mhz;
    logic       rst;
    logic       ps2_clk;
    logic       ps2_data;
    logic       kbd_read_en;
    logic [7:0] button_code;
    logic       kbd_ready;
    int         i;

    // PS/2 clock is ~10-16 kHz in real hardware; use a period that is
    // comfortably slower than the 3-bit falling-edge filter in the DUT.
    localparam int PS2_HALF_PERIOD = 20;  // clk_100mhz cycles

    // --- Instantiate ps2_keyboard ---
    ps2_keyboard dut (
        .clk_100mhz  (clk_100mhz),
        .rst         (rst),

        .ps2_clk     (ps2_clk),
        .ps2_data    (ps2_data),

        .kbd_read_en (kbd_read_en),
        .button_code (button_code),
        .kbd_ready   (kbd_ready)
    );

    // --- Clock generator ---
    initial clk_100mhz = 0;
    always #5 clk_100mhz = ~clk_100mhz;

    // --- Drive one PS/2 bit: set data, then pulse ps2_clk low/high ---
    task automatic send_bit(input logic value);
        begin
            ps2_data = value;
            repeat (2) @(posedge clk_100mhz);  // let data settle before the edge
            ps2_clk = 1'b0;
            repeat (PS2_HALF_PERIOD) @(posedge clk_100mhz);
            ps2_clk = 1'b1;
            repeat (PS2_HALF_PERIOD) @(posedge clk_100mhz);
        end
    endtask

    // --- Drive a full PS/2 frame: start(0) + 8 data (LSB first) + odd parity + stop(1) ---
    task automatic send_scan_code(input logic [7:0] code);
        logic parity;
        begin
            parity = ~^code;  // odd parity: 1 if code has an even number of 1s
            send_bit(1'b0);   // start bit
            for (i = 0; i < 8; i = i + 1) begin
                send_bit(code[i]);
            end
            send_bit(parity);
            send_bit(1'b1);   // stop bit
        end
    endtask

    // --- Test cases ---
    initial begin
        $dumpfile("sim_ps2_keyboard.vcd");
        $dumpvars(0, tb_ps2_keyboard);

        // --- Initialize signals ---
        rst         = 0;
        ps2_clk     = 1'b1;   // idle HIGH
        ps2_data    = 1'b1;   // idle HIGH
        kbd_read_en = 0;

        // --- Apply reset ---
        @(posedge clk_100mhz);
        #1;
        @(posedge clk_100mhz);
        #1;

        rst = 1;
        #1;
        @(posedge clk_100mhz);
        #1;

        // --- Test 1: Reset state ---
        if (kbd_ready == 1'b0 && button_code == 8'h00)
            $display("PASS: kbd_ready=0 and button_code=0x00 after reset");
        else
            $display("FAIL: expected kbd_ready=0, button_code=0x00 after reset, got kbd_ready=%0b button_code=0x%02h",
                      kbd_ready, button_code);

        // --- Test 2: Send scan code 0x1C ('A' make code) and check capture ---
        send_scan_code(8'h1C);
        repeat (5) @(posedge clk_100mhz);
        #1;

        if (kbd_ready == 1'b1)
            $display("PASS: kbd_ready asserted after valid frame");
        else
            $display("FAIL: kbd_ready expected 1 after valid frame, got %0b", kbd_ready);

        if (button_code == 8'h1C)
            $display("PASS: button_code = 0x1C");
        else
            $display("FAIL: button_code expected 0x1C, got 0x%02h", button_code);

        // --- Test 3: kbd_read_en clears kbd_ready ---
        kbd_read_en = 1'b1;
        @(posedge clk_100mhz);
        #1;
        kbd_read_en = 1'b0;

        if (kbd_ready == 1'b0)
            $display("PASS: kbd_ready cleared after kbd_read_en pulse");
        else
            $display("FAIL: kbd_ready expected 0 after read, got %0b", kbd_ready);

        // --- Test 4: Second scan code (break code prefix 0xF0) captured independently ---
        send_scan_code(8'hF0);
        repeat (5) @(posedge clk_100mhz);
        #1;

        if (kbd_ready == 1'b1 && button_code == 8'hF0)
            $display("PASS: second frame captured, button_code = 0xF0");
        else
            $display("FAIL: expected kbd_ready=1 button_code=0xF0, got kbd_ready=%0b button_code=0x%02h",
                      kbd_ready, button_code);

        // --- Test 5: Reset clears kbd_ready mid-stream ---
        rst = 0;
        @(posedge clk_100mhz);
        #1;
        if (kbd_ready == 1'b0 && button_code == 8'h00)
            $display("PASS: kbd_ready and button_code cleared on reset");
        else
            $display("FAIL: expected kbd_ready=0 button_code=0x00 after reset, got kbd_ready=%0b button_code=0x%02h",
                      kbd_ready, button_code);
        rst = 1;
        @(posedge clk_100mhz);
        #1;

        $display("All PS/2 keyboard tests completed.");
        $finish;
    end

endmodule
