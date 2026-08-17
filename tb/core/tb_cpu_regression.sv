// ============================================================
// Module  : tb_cpu_regression
// Purpose : Broader CPU regression testbench
//           Covers arithmetic, load/store handshakes, branches,
//           and jump/link behavior using a simple memory model.
// ============================================================

import riscv_pkg::*;
import alu_ops::*;

module tb_cpu_regression;

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

    logic [31:0] imem [0:255];
    logic [31:0] dmem [0:255];

    int error_count;
    int cycle_count;
    logic store_seen;
    logic load_seen;

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

    // Synchronous models matching real imem.sv / dmem.sv registered outputs.
    // dmem uses addr[9:2] (256-entry array) so addresses like 0x20000000
    // map to index 0 — the upper region bits are stripped, matching how the
    // real DMEM only decodes the low 14 address bits inside its 16 KB window.
    always_ff @(posedge clk)
        imem_data <= imem[imem_addr[31:2]];

    always_ff @(posedge clk) begin
        dmem_read_data <= dmem[dmem_addr[9:2]];
        if (dmem_write_en) begin
            if (dmem_byte_enable[0]) dmem[dmem_addr[9:2]][7:0]   <= dmem_write_data[7:0];
            if (dmem_byte_enable[1]) dmem[dmem_addr[9:2]][15:8]  <= dmem_write_data[15:8];
            if (dmem_byte_enable[2]) dmem[dmem_addr[9:2]][23:16] <= dmem_write_data[23:16];
            if (dmem_byte_enable[3]) dmem[dmem_addr[9:2]][31:24] <= dmem_write_data[31:24];
            store_seen <= 1'b1;
        end
        if (dmem_read_en)
            load_seen <= 1'b1;
    end

    function automatic [31:0] encode_i(
        input int imm,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        encode_i = {imm[11:0], rs1, funct3, rd, opcode};
    endfunction

    function automatic [31:0] encode_r(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        encode_r = {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic [31:0] encode_s(
        input int imm,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [6:0] opcode
    );
        encode_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    function automatic [31:0] encode_b(
        input int imm,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [6:0] opcode
    );
        encode_b = {
            imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode
        };
    endfunction

    function automatic [31:0] encode_j(
        input int imm,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        encode_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
    endfunction

    function automatic [31:0] encode_u(
        input int imm,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        encode_u = {imm[31:12], rd, opcode};
    endfunction

    task automatic check_reg(
        input logic [4:0] reg_idx,
        input logic [31:0] expected,
        input string name
    );
        logic [31:0] actual;
        begin
            actual = dut.u_datapath.u_register_file.registers[reg_idx];
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("FAIL: %s expected 0x%08h, got 0x%08h", name, expected, actual);
            end
            else begin
                $display("PASS: %s = 0x%08h", name, actual);
            end
        end
    endtask

    integer i;
    initial begin
        $dumpfile("sim_cpu_regression.vcd");
        $dumpvars(0, tb_cpu_regression);

        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 32'h00000013; // NOP
            dmem[i] = 32'h00000000;
        end

        // Arithmetic smoke.
        imem[0]  = encode_i(5,  5'd0, F3_ADD_SUB, 5'd1, OP_I_ALU);          // addi x1, x0, 5
        imem[1]  = encode_i(7,  5'd0, F3_ADD_SUB, 5'd2, OP_I_ALU);          // addi x2, x0, 7
        imem[2]  = encode_r(F7_NORMAL, 5'd2, 5'd1, F3_ADD_SUB, 5'd3, OP_R); // add  x3, x1, x2

        // Memory path smoke using the real DMEM base address (0x20000000).
        imem[3]  = encode_u(32'h20000000, 5'd5, OP_LUI);                     // lui  x5, 0x20000
        imem[4]  = encode_s(0,  5'd3, 5'd5, F3_SW, OP_S);                    // sw   x3, 0(x5)
        imem[5]  = encode_i(0,  5'd5, F3_LW, 5'd4, OP_I_LOAD);               // lw   x4, 0(x5)

        // Branch should not be taken because x1 == x1 for BNE.
        imem[6]  = encode_b(8,  5'd1, 5'd1, F3_BNE, OP_B);                   // bne  x1, x1, +8
        imem[7]  = encode_i(9,  5'd0, F3_ADD_SUB, 5'd8, OP_I_ALU);           // addi x8, x0, 9

        // JAL at imem[8] (PC=0x20): link = 0x24 = 36; target = imem[10].
        imem[8]  = encode_j(8,  5'd6, OP_JAL);                               // jal  x6, +8
        imem[9]  = encode_i(1,  5'd0, F3_ADD_SUB, 5'd10, OP_I_ALU);          // addi x10, x0, 1  (skipped)
        imem[10] = encode_i(2,  5'd0, F3_ADD_SUB, 5'd10, OP_I_ALU);          // addi x10, x0, 2

        rst_n = 1'b0;
        error_count = 0;
        cycle_count = 0;
        store_seen = 1'b0;
        load_seen = 1'b0;

        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;

        repeat (80) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        check_reg(5'd1,  32'd5,  "x1");
        check_reg(5'd2,  32'd7,  "x2");
        check_reg(5'd3,  32'd12, "x3");
        check_reg(5'd4,  32'd12, "x4 load result");
        check_reg(5'd6,  32'd36, "x6 jal link");
        check_reg(5'd8,  32'd9,  "x8 branch fall-through");
        check_reg(5'd10, 32'd2,  "x10 jal target");

        if (!store_seen) begin
            error_count = error_count + 1;
            $display("FAIL: store handshake never asserted");
        end
        else begin
            $display("PASS: store handshake observed");
        end

        if (!load_seen) begin
            error_count = error_count + 1;
            $display("FAIL: load handshake never asserted");
        end
        else begin
            $display("PASS: load handshake observed");
        end

        if (dmem[0] !== 32'd12) begin
            error_count = error_count + 1;
            $display("FAIL: dmem[0] expected 0x0000000c, got 0x%08h", dmem[0]);
        end
        else begin
            $display("PASS: dmem[0] = 0x%08h", dmem[0]);
        end

        if (error_count != 0) begin
            $display("CPU regression failed with %0d error(s).", error_count);
            $fatal(1);
        end

        $display("CPU regression passed.");
        $finish;
    end

endmodule
