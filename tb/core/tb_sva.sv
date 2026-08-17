// ============================================================
// Module  : tb_sva
// Purpose : SVA-style property checks for the CPU core.
//           Runs the ISA diagnostic as a stimulus generator
//           while 5 clocked assertions fire on every cycle.
//           Uses immediate assertions inside always @(posedge clk)
//           — the Icarus-compatible substitute for concurrent
//           assert property(…) blocks.
//
// Properties verified:
//   P1 — PC is always word-aligned (imem_addr[1:0] == 2'b00)
//   P2 — dmem_write_en and dmem_read_en are mutually exclusive
//   P3 — FSM never enters the undefined state 3'b111
//   P4 — No DMEM access occurs during STATE_FETCH or STATE_DECODE
//   P5 — When dmem_write_en is asserted, at least one byte lane is enabled
// ============================================================

import riscv_pkg::*;

module tb_sva;

    // --- Signals ---
    logic        clk;
    logic        rst_n;
    logic [31:0] imem_addr;
    logic [31:0] imem_data;
    logic [31:0] dmem_addr;
    logic [31:0] dmem_write_data;
    logic [3:0]  dmem_byte_enable;
    logic        dmem_write_en;
    logic        dmem_read_en;
    logic [31:0] dmem_read_data;

    logic [31:0] imem_mem [0:8191];
    logic [31:0] dmem_mem [0:8191];
    int cycle_count;
    int assert_fail_count;

    // --- DUT ---
    cpu dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .irq_m_timer      (1'b0),
        .irq_m_external   (1'b0),
        .imem_addr        (imem_addr),
        .imem_data        (imem_data),
        .dmem_addr        (dmem_addr),
        .dmem_write_data  (dmem_write_data),
        .dmem_byte_enable (dmem_byte_enable),
        .dmem_write_en    (dmem_write_en),
        .dmem_read_en     (dmem_read_en),
        .dmem_read_data   (dmem_read_data)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Combinational memory model — matches the one-cycle FETCH→DECODE
    // window the CPU uses to latch instructions.
    assign imem_data = imem_mem[imem_addr[14:2]];
    assign dmem_read_data = (dmem_addr[31:28] == 4'h2) ? dmem_mem[dmem_addr[14:2]] : 32'h0;

    always_ff @(posedge clk) begin
        if (dmem_write_en && dmem_addr[31:28] == 4'h2) begin
            if (dmem_byte_enable[0]) dmem_mem[dmem_addr[14:2]][7:0]   <= dmem_write_data[7:0];
            if (dmem_byte_enable[1]) dmem_mem[dmem_addr[14:2]][15:8]  <= dmem_write_data[15:8];
            if (dmem_byte_enable[2]) dmem_mem[dmem_addr[14:2]][23:16] <= dmem_write_data[23:16];
            if (dmem_byte_enable[3]) dmem_mem[dmem_addr[14:2]][31:24] <= dmem_write_data[31:24];
        end
    end

    // ============================================================
    // Property checks
    // ============================================================

    // P1 — PC is always word-aligned.
    // imem_addr is the CPU's PC register directly (assign imem_addr = pc).
    always @(posedge clk) begin
        if (rst_n)
            assert(imem_addr[1:0] == 2'b00) else begin
                $error("SVA FAIL P1: PC not word-aligned: imem_addr=0x%08h", imem_addr);
                assert_fail_count++;
            end
    end

    // P2 — DMEM read enable and write enable are mutually exclusive.
    // The multi-cycle FSM is always in exactly one state, so it can never
    // issue both a load and a store in the same cycle.
    always @(posedge clk) begin
        if (rst_n)
            assert(!(dmem_write_en && dmem_read_en)) else begin
                $error("SVA FAIL P2: dmem_write_en and dmem_read_en simultaneously asserted");
                assert_fail_count++;
            end
    end

    // P3 — FSM never reaches the unused state 3'b111.
    // States 0-6 are defined; 3'b111 = 7 has no transition into it.
    always @(posedge clk) begin
        if (rst_n)
            assert(dut.u_control_unit.current_state != 3'b111) else begin
                $error("SVA FAIL P3: FSM entered undefined state 3'b111");
                assert_fail_count++;
            end
    end

    // P4 — No DMEM access occurs during STATE_FETCH or STATE_DECODE.
    // Only STATE_MEMORY can drive dmem_write_en or dmem_read_en.
    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.u_control_unit.current_state == STATE_FETCH ||
                dut.u_control_unit.current_state == STATE_DECODE)
                assert(!dmem_write_en && !dmem_read_en) else begin
                    $error("SVA FAIL P4: DMEM access during state %0b",
                           dut.u_control_unit.current_state);
                    assert_fail_count++;
                end
        end
    end

    // P5 — A write with no byte enables enabled is a bug.
    always @(posedge clk) begin
        if (rst_n)
            assert(!(dmem_write_en && (dmem_byte_enable == 4'b0))) else begin
                $error("SVA FAIL P5: dmem_write_en=1 but dmem_byte_enable=4'b0");
                assert_fail_count++;
            end
    end

    // ============================================================
    // Stimulus: run the ISA diagnostic as the property witness
    // ============================================================
    localparam STATUS_WORD = 0;  // dmem_mem[0] = 0x20000000
    localparam DETAIL_WORD = 1;  // dmem_mem[1] = 0x20000004
    localparam PASS_SIG = 32'h1A5A1A5A;
    localparam FAIL_SIG = 32'h0BAD0BAD;

    integer i;
    initial begin
        $dumpfile("sim_sva.vcd");
        $dumpvars(0, tb_sva);

        assert_fail_count = 0;

        for (i = 0; i < 8192; i++) begin
            imem_mem[i] = 32'h00000013;
            dmem_mem[i] = 32'h0;
        end

        $readmemh("sw/tests/isa_diag.mem", imem_mem);

        rst_n = 1'b0;
        cycle_count = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;

        while (cycle_count < 4000) begin
            @(posedge clk);
            cycle_count++;

            if (dmem_mem[STATUS_WORD] == PASS_SIG) begin
                if (assert_fail_count != 0) begin
                    $display("FAIL: SVA — %0d violation(s) over %0d cycles",
                             assert_fail_count, cycle_count);
                    $fatal(1);
                end
                $display("PASS: SVA — all 5 properties held over %0d cycles", cycle_count);
                $finish;
            end

            if (dmem_mem[STATUS_WORD] == FAIL_SIG) begin
                $display("FAIL: ISA diagnostic failed during SVA run (detail=0x%08h)",
                         dmem_mem[DETAIL_WORD]);
                $fatal(1);
            end
        end

        $display("FAIL: SVA test timed out after %0d cycles", cycle_count);
        $fatal(1);
    end

endmodule
