// ============================================================
// Module  : tb_riscv_tests
// Purpose : Generic harness for running one riscv-tests binary.
//
// Usage (from Makefile):
//   vvp sim_riscv_tests.vvp +test=sw/riscv-tests/rv32ui-p-add
//
// The testbench loads <test>.mem into IMEM, resets the CPU,
// and polls DMEM[0] (= tohost at 0x20000000) for completion:
//   tohost == 1              PASS
//   tohost == (N<<1)|1       FAIL in test case N
//   no activity in 100 000 cycles → TIMEOUT
// ============================================================

import riscv_pkg::*;
import alu_ops::*;

module tb_riscv_tests;

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

    // 16 KB IMEM (4096 words) and 16 KB DMEM (4096 words)
    logic [31:0] imem [0:4095];
    logic [31:0] dmem [0:4095];

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

    // Synchronous IMEM — index by word address (bits[13:2] for 16 KB window)
    always_ff @(posedge clk)
        imem_data <= imem[imem_addr[13:2]];

    // Synchronous DMEM — strip the 0x20000000 base via bits[13:2]
    always_ff @(posedge clk) begin
        dmem_read_data <= dmem[dmem_addr[13:2]];
        if (dmem_write_en) begin
            if (dmem_byte_enable[0]) dmem[dmem_addr[13:2]][7:0]   <= dmem_write_data[7:0];
            if (dmem_byte_enable[1]) dmem[dmem_addr[13:2]][15:8]  <= dmem_write_data[15:8];
            if (dmem_byte_enable[2]) dmem[dmem_addr[13:2]][23:16] <= dmem_write_data[23:16];
            if (dmem_byte_enable[3]) dmem[dmem_addr[13:2]][31:24] <= dmem_write_data[31:24];
        end
    end

    // ----------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------
    string test_path;
    string mem_file;
    string dmem_file;

    integer i;
    integer cycle;
    logic [31:0] tohost_val;
    initial begin
        $dumpfile("sim_riscv_tests.vcd");
        $dumpvars(0, tb_riscv_tests);


        if (!$value$plusargs("test=%s", test_path)) begin
            $display("ERROR: +test=<path> argument required");
            $fatal(1);
        end
        mem_file  = {test_path, ".mem"};
        dmem_file = {test_path, ".dmem.mem"};

        // Initialise memories
        for (i = 0; i < 4096; i++) begin imem[i] = 32'h0000_0013; dmem[i] = 0; end
        $readmemh(mem_file, imem);
        $readmemh(dmem_file, dmem);

        // Reset
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // Run until tohost written or timeout
        cycle      = 0;
        tohost_val = 0;
        while (cycle < 100_000 && tohost_val == 0) begin
            @(posedge clk);
            cycle++;
            tohost_val = dmem[0];   // tohost is always DMEM word 0
        end

        if (tohost_val == 32'h1) begin
            $display("PASS: %s", test_path);
        end else if (tohost_val == 0) begin
            $display("FAIL: %s — TIMEOUT after %0d cycles", test_path, cycle);
            $fatal(1);
        end else begin
            $display("FAIL: %s — test case %0d (tohost=0x%08h)",
                     test_path, tohost_val >> 1, tohost_val);
            $fatal(1);
        end

        $finish;
    end

endmodule
