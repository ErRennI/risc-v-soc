// ============================================================
// Module  : cpu
// Purpose : Top-level RV32IM CPU core
//           Instantiates and connects control_unit and datapath
// ============================================================
module cpu #(
    parameter logic [31:0] PC_RESET = 32'h0000_7800
) (
    input  logic        clk,
    input  logic        rst_n,

    // Interrupts from peripheral bus
    input  logic        irq_m_timer,
    input  logic        irq_m_external,

    // Instruction memory interface
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_data,

    // Data memory interface
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_write_data,
    output logic [3:0]  dmem_byte_enable,
    output logic        dmem_write_en,
    output logic        dmem_read_en,
    input  logic [31:0] dmem_read_data
);

    // Internal wires connecting control unit and datapath
    logic [31:0] instruction;
    logic        branch_eq;
    logic        branch_lt;
    logic        branch_ltu;
    logic [4:0]  alu_operation;
    logic [1:0]  alu_src_a_sel;
    logic        alu_src_b;
    logic        reg_write;
    logic        mem_read;
    logic        mem_write;
    logic        mem_to_reg;
    logic        jump;
    logic [1:0]  pc_src;
    logic        instr_latch_en;
    logic        pc_write_en;
    logic        alu_reg_en;
    logic        mdu_start;
    logic        mdu_done;
    logic        irq_pending;
    logic        irq_cause_external;
    logic        trap_en;
    logic        mret_en;
    logic        csr_reg_en;
    logic        csr_write_en;
    logic [31:0] trap_cause;
    logic        mem_addr_misaligned;
    logic        fetch_addr_misaligned;
    logic        in_second_pass;
    logic        instret_en;

    control_unit u_control_unit (
        .clk                  (clk),
        .rst_n                (rst_n),
        .instruction          (instruction),
        .branch_eq            (branch_eq),
        .branch_lt            (branch_lt),
        .branch_ltu           (branch_ltu),
        .mdu_done             (mdu_done),
        .irq_pending          (irq_pending),
        .irq_cause_external   (irq_cause_external),
        .mem_addr_misaligned  (mem_addr_misaligned),
        .fetch_addr_misaligned(fetch_addr_misaligned),
        .alu_src_a_sel        (alu_src_a_sel),
        .alu_operation        (alu_operation),
        .alu_src_b            (alu_src_b),
        .reg_write            (reg_write),
        .mem_read             (mem_read),
        .mem_write            (mem_write),
        .mem_to_reg           (mem_to_reg),
        .jump                 (jump),
        .pc_src               (pc_src),
        .instr_latch_en       (instr_latch_en),
        .pc_write_en          (pc_write_en),
        .alu_reg_en           (alu_reg_en),
        .mdu_start            (mdu_start),
        .trap_en              (trap_en),
        .mret_en              (mret_en),
        .csr_reg_en           (csr_reg_en),
        .csr_write_en         (csr_write_en),
        .trap_cause           (trap_cause),
        .in_second_pass       (in_second_pass),
        .instret_en           (instret_en)
    );

    datapath #(
        .PC_RESET             (PC_RESET)
    ) u_datapath (
        .clk                  (clk),
        .rst_n                (rst_n),
        .alu_src_a_sel        (alu_src_a_sel),
        .alu_operation        (alu_operation),
        .alu_src_b            (alu_src_b),
        .reg_write            (reg_write),
        .mem_read             (mem_read),
        .mem_write            (mem_write),
        .mem_to_reg           (mem_to_reg),
        .jump                 (jump),
        .pc_src               (pc_src),
        .instr_latch_en       (instr_latch_en),
        .pc_write_en          (pc_write_en),
        .alu_reg_en           (alu_reg_en),
        .mdu_start            (mdu_start),
        .mdu_done             (mdu_done),
        .trap_en              (trap_en),
        .mret_en              (mret_en),
        .csr_reg_en           (csr_reg_en),
        .csr_write_en         (csr_write_en),
        .trap_cause           (trap_cause),
        .mem_addr_misaligned  (mem_addr_misaligned),
        .fetch_addr_misaligned(fetch_addr_misaligned),
        .in_second_pass       (in_second_pass),
        .instret_en           (instret_en),
        .irq_m_timer          (irq_m_timer),
        .irq_m_external       (irq_m_external),
        .irq_pending          (irq_pending),
        .irq_cause_external   (irq_cause_external),
        .imem_addr            (imem_addr),
        .imem_data            (imem_data),
        .dmem_addr            (dmem_addr),
        .dmem_write_data      (dmem_write_data),
        .dmem_byte_enable     (dmem_byte_enable),
        .dmem_write_en        (dmem_write_en),
        .dmem_read_en         (dmem_read_en),
        .dmem_read_data       (dmem_read_data),
        .instruction          (instruction),
        .branch_eq            (branch_eq),
        .branch_lt            (branch_lt),
        .branch_ltu           (branch_ltu)
    );

endmodule
