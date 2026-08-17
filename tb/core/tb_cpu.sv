// ============================================================
// Module  : tb_cpu
// Purpose : CPU integration testbench
//           Tests basic instruction execution using
//           a memory model array
// ============================================================

import riscv_pkg::*;
import alu_ops::*;

module tb_cpu;

    // --- Clock and reset ---
    logic        clk;
    logic        rst_n;

    // --- Instruction memory interface ---
    logic [31:0] imem_addr;
    logic [31:0] imem_data;

    // --- Data memory interface ---
    logic [31:0] dmem_addr;
    logic [31:0] dmem_write_data;
    logic [3:0]  dmem_byte_enable;
    logic        dmem_write_en;
    logic        dmem_read_en;
    logic [31:0] dmem_read_data;

    // --- Fake instruction memory ---
    logic [31:0] imem [0:255];

    // --- Fake data memory ---
    logic [31:0] dmem [0:255];

    // --- CPU instantiation ---
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

    // --- Clock generator ---
    initial clk = 0;
    always #5 clk = ~clk;

    // --- Instruction memory model (synchronous, matches real imem.sv) ---
    always_ff @(posedge clk)
        imem_data <= imem[imem_addr[31:2]];

    // --- Data memory model (synchronous, matches real dmem.sv) ---
    always_ff @(posedge clk) begin
        dmem_read_data <= dmem[dmem_addr[31:2]];
        if (dmem_write_en) begin
            if (dmem_byte_enable[0]) dmem[dmem_addr[31:2]][7:0]   <= dmem_write_data[7:0];
            if (dmem_byte_enable[1]) dmem[dmem_addr[31:2]][15:8]  <= dmem_write_data[15:8];
            if (dmem_byte_enable[2]) dmem[dmem_addr[31:2]][23:16] <= dmem_write_data[23:16];
            if (dmem_byte_enable[3]) dmem[dmem_addr[31:2]][31:24] <= dmem_write_data[31:24];
        end
    end

    // --- Test program ---
    integer i;
    initial begin
        $dumpfile("sim_cpu.vcd");
        $dumpvars(0, tb_cpu);

        // Initialize memories to zero
        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 32'b0;
            dmem[i] = 32'b0;
        end

        // Load test program
        imem[0] = 32'h00500093; // ADDI x1, x0, 5
        imem[1] = 32'h00A00113; // ADDI x2, x0, 10
        imem[2] = 32'h002081B3; // ADD  x3, x1, x2

        // Apply reset
        rst_n = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;

        repeat(20) @(posedge clk);
        #1;

        if (dut.u_datapath.u_register_file.registers[1] == 32'd5)
            $display("PASS: x1 = 5");
        else
            $display("FAIL: x1 expected 5, got %0d", dut.u_datapath.u_register_file.registers[1]);

        if (dut.u_datapath.u_register_file.registers[2] == 32'd10)
            $display("PASS: x2 = 10");
        else
            $display("FAIL: x2 expected 10, got %0d", dut.u_datapath.u_register_file.registers[2]);

        if (dut.u_datapath.u_register_file.registers[3] == 32'd15)
            $display("PASS: x3 = 15");
        else
            $display("FAIL: x3 expected 15, got %0d", dut.u_datapath.u_register_file.registers[3]);
        
        $display("All CPU tests completed.");
        $finish;
    end

endmodule
