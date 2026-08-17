// ============================================================
// Module  : datapath
// Purpose : CPU datapath for RV32IM multi-cycle implementation
//           Connects PC, register file, ALU, immediate generator,
//           MDU, and CSR file.
// ============================================================

import riscv_pkg::*;
import alu_ops::*;

module datapath #(
    parameter logic [31:0] PC_RESET = 32'h0000_7800
) (
    input  logic        clk,
    input  logic        rst_n,

    // Control signals from control unit
    input  logic [1:0]  alu_src_a_sel,
    input  logic [4:0]  alu_operation,
    input  logic        alu_src_b,
    input  logic        reg_write,
    input  logic        mem_read,
    input  logic        mem_write,
    input  logic        mem_to_reg,
    input  logic        jump,
    input  logic [1:0]  pc_src,
    input  logic        instr_latch_en,
    input  logic        pc_write_en,
    input  logic        alu_reg_en,
    input  logic        mdu_start,
    output logic        mdu_done,

    // CSR / trap control signals
    input  logic        trap_en,
    input  logic        mret_en,
    input  logic        csr_reg_en,
    input  logic        csr_write_en,
    input  logic [31:0] trap_cause,       // MCAUSE value to pass to csr_file

    // Alignment fault detection (to control_unit, combinational)
    output logic        mem_addr_misaligned,   // HIGH when load/store crosses a word boundary
    output logic        fetch_addr_misaligned, // branch/JAL/JALR target not 4-byte aligned

    // Second-pass flag from control_unit (HIGH in STATE_MEMORY2)
    input  logic        in_second_pass,

    // Instruction retirement pulse (HIGH in the cycle an instruction retires)
    input  logic        instret_en,

    // External interrupt requests
    input  logic        irq_m_timer,
    input  logic        irq_m_external,
    output logic        irq_pending,
    output logic        irq_cause_external,

    // Instruction memory interface
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_data,

    // Data memory interface
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_write_data,
    output logic [3:0]  dmem_byte_enable,
    output logic        dmem_write_en,
    output logic        dmem_read_en,
    input  logic [31:0] dmem_read_data,

    // Status signals to control unit
    output logic [31:0] instruction,
    output logic        branch_eq,
    output logic        branch_lt,
    output logic        branch_ltu
);

    // --------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------
    logic [31:0] pc;
    logic [31:0] pc_next;
    logic [31:0] pc_plus4;
    logic [31:0] pc_branch;
    logic [31:0] imm;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] alu_operand_a;
    logic [31:0] alu_operand_b;
    logic [31:0] alu_result;
    logic        alu_zero;
    logic [31:0] alu_result_reg;
    logic [31:0] write_back_data;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic [2:0]  funct3;
    logic [7:0]  load_byte;
    logic [15:0] load_half_assembled;
    logic [31:0] load_word_assembled;
    logic [31:0] load_data_formatted;
    logic [31:0] dmem_data_buf;        // buffers first word for cross-boundary loads

    // CSR interface signals
    logic [31:0] csr_rdata;
    logic [31:0] mtvec_out;
    logic [31:0] mepc_out;
    logic [31:0] csr_wdata;
    logic [1:0]  csr_op;
    logic [31:0] trap_val;

    // --------------------------------------------------------
    // Instruction register
    // --------------------------------------------------------
    logic [31:0] instr_reg;

    always_ff @(posedge clk) begin
        if (!rst_n)
            instr_reg <= 32'b0;
        else if (instr_latch_en)
            instr_reg <= imem_data;
    end

    assign instruction = instr_reg;

    // --------------------------------------------------------
    // Instruction field extraction
    // --------------------------------------------------------
    assign rs1    = instr_reg[19:15];
    assign rs2    = instr_reg[24:20];
    assign rd     = instr_reg[11:7];
    assign funct3 = instr_reg[14:12];

    // --------------------------------------------------------
    // ALU result / MDU result register
    // Also captures old CSR value when csr_reg_en is asserted
    // in STATE_EXECUTE, so the write-back MUX can forward it
    // to rd in STATE_WRITEBACK via the normal alu_result_reg path.
    // --------------------------------------------------------
    logic [31:0] mdu_result;
    logic        mdu_busy_unused;

    always_ff @(posedge clk) begin
        if (!rst_n)
            alu_result_reg <= 32'b0;
        else if (csr_reg_en)
            alu_result_reg <= csr_rdata;
        else if (alu_reg_en)
            alu_result_reg <= alu_result;
        else if (mdu_done)
            alu_result_reg <= mdu_result;
    end

    // --------------------------------------------------------
    // First-word buffer for cross-boundary loads
    // Latches the DMEM output (word N) at the edge leaving STATE_MEMORY2,
    // so WRITEBACK has both word N (here) and word N+1 (dmem_read_data).
    // --------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n)
            dmem_data_buf <= 32'b0;
        else if (in_second_pass)
            dmem_data_buf <= dmem_read_data;
    end

    // --------------------------------------------------------
    // Program Counter
    // --------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n)
            pc <= PC_RESET;
        else if (pc_write_en)
            pc <= pc_next;
    end

    assign pc_plus4  = pc + 32'd4;
    assign pc_branch = pc + imm;

    always @(*) begin
        if (trap_en)
            pc_next = mtvec_out;
        else if (mret_en)
            pc_next = mepc_out;
        else begin
            case (pc_src)
                2'b00:   pc_next = pc_plus4;
                2'b01:   pc_next = pc_branch;
                2'b10:   pc_next = (rs1_data + imm) & ~32'b1;
                default: pc_next = pc_branch;
            endcase
        end
    end

    assign imem_addr = pc;

    // --------------------------------------------------------
    // Submodule instantiations
    // --------------------------------------------------------

    imm_gen u_imm_gen (
        .instruction (instr_reg),
        .imm_out     (imm)
    );

    register_file u_register_file (
        .clk          (clk),
        .read_addr_1  (rs1),
        .read_data_1  (rs1_data),
        .read_addr_2  (rs2),
        .read_data_2  (rs2_data),
        .write_enable (reg_write),
        .write_addr   (rd),
        .write_data   (write_back_data)
    );

    always @(*) begin
        case (alu_src_a_sel)
            2'b01:   alu_operand_a = pc;
            2'b10:   alu_operand_a = 32'b0;
            default: alu_operand_a = rs1_data;
        endcase
    end

    assign alu_operand_b = alu_src_b ? imm : rs2_data;

    alu u_alu (
        .operation (alu_operation),
        .operand_a (alu_operand_a),
        .operand_b (alu_operand_b),
        .result    (alu_result),
        .zero      (alu_zero)
    );

    mdu u_mdu (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (mdu_start),
        .operation (alu_operation),
        .operand_a (alu_operand_a),
        .operand_b (alu_operand_b),
        .result    (mdu_result),
        .busy      (mdu_busy_unused),
        .done      (mdu_done)
    );

    // CSR write data: rs1_data for register variants (funct3[2]=0),
    // zero-extended zimm for immediate variants (funct3[2]=1).
    assign csr_wdata = funct3[2] ? {27'b0, instr_reg[19:15]} : rs1_data;

    // CSR operation encoding from funct3[1:0]:
    //   01 (CSRRW/CSRRWI) → 00 (overwrite)
    //   10 (CSRRS/CSRRSI) → 01 (set bits)
    //   11 (CSRRC/CSRRCI) → 10 (clear bits)
    always @(*) begin
        case (funct3[1:0])
            2'b10:   csr_op = 2'b01;
            2'b11:   csr_op = 2'b10;
            default: csr_op = 2'b00;
        endcase
    end

    // --------------------------------------------------------
    // Cross-word-boundary detection (combinational from ALU result)
    // Asserts when a load/store spans two words and needs STATE_MEMORY2.
    // Within-word misalignment (e.g. lh at offset 1) is handled in-place with no extra cycle.
    // --------------------------------------------------------
    always @(*) begin
        case (funct3)
            F3_LW, F3_SW:          mem_addr_misaligned = |alu_result[1:0];        // any non-word-aligned crosses
            F3_LH, F3_LHU, F3_SH:  mem_addr_misaligned = &alu_result[1:0];        // only offset==3 crosses
            default:                mem_addr_misaligned = 1'b0;                    // byte: never crosses
        endcase
    end

    // --------------------------------------------------------
    // Fetch address misalignment check (JALR, JAL, taken branches)
    // fetch_target is the computed destination address.
    // --------------------------------------------------------
    logic [31:0] fetch_target;

    always @(*) begin
        if (instr_reg[6:0] == OP_JALR) begin
            fetch_target          = (rs1_data + imm) & ~32'b1;
            fetch_addr_misaligned = fetch_target[1];
        end else begin                          // OP_B, OP_JAL
            fetch_target          = pc_branch;
            fetch_addr_misaligned = pc_branch[1];
        end
    end

    // --------------------------------------------------------
    // Trap value for MTVAL (combinational)
    // --------------------------------------------------------
    always @(*) begin
        case (trap_cause)
            EXC_FETCH_MISALIGN:              trap_val = fetch_target;    // misaligned jump/branch target
            EXC_LOAD_MISALIGN,
            EXC_STORE_MISALIGN:              trap_val = alu_result_reg;  // faulting effective address
            EXC_ILLEGAL_INSTR:               trap_val = instr_reg;       // offending instruction word
            default:                         trap_val = 32'b0;
        endcase
    end

    csr_file u_csr_file (
        .clk              (clk),
        .rst_n            (rst_n),
        .trap_en          (trap_en),
        .mret_en          (mret_en),
        .trap_cause       (trap_cause),
        .trap_val         (trap_val),
        .trap_pc          (pc),
        .irq_m_timer      (irq_m_timer),
        .irq_m_external   (irq_m_external),
        .csr_addr         (instr_reg[31:20]),
        .csr_wdata        (csr_wdata),
        .csr_op           (csr_op),
        .csr_write_en     (csr_write_en),
        .instret_en       (instret_en),
        .csr_rdata        (csr_rdata),
        .mtvec_out        (mtvec_out),
        .mepc_out         (mepc_out),
        .irq_pending      (irq_pending),
        .irq_cause_external(irq_cause_external)
    );

    // --------------------------------------------------------
    // Load data formatting — supports all aligned and misaligned cases
    // --------------------------------------------------------

    // lb/lbu: single byte at byte offset alu_result_reg[1:0] within the word
    always @(*) begin
        case (alu_result_reg[1:0])
            2'b00:   load_byte = dmem_read_data[7:0];
            2'b01:   load_byte = dmem_read_data[15:8];
            2'b10:   load_byte = dmem_read_data[23:16];
            default: load_byte = dmem_read_data[31:24];
        endcase
    end

    // lh/lhu: 16-bit value from all four byte offsets
    //   off=0: [15:0]  (aligned)
    //   off=1: [23:8]  (within-word misaligned — single read)
    //   off=2: [31:16] (aligned)
    //   off=3: {word_N+1[7:0], word_N[31:24]} (cross-boundary — two reads)
    always @(*) begin
        case (alu_result_reg[1:0])
            2'b00:   load_half_assembled = dmem_read_data[15:0];
            2'b01:   load_half_assembled = dmem_read_data[23:8];
            2'b10:   load_half_assembled = dmem_read_data[31:16];
            default: load_half_assembled = {dmem_read_data[7:0], dmem_data_buf[31:24]};
        endcase
    end

    // lw: 32-bit value; any non-zero offset is cross-boundary and uses dmem_data_buf + dmem_read_data
    always @(*) begin
        case (alu_result_reg[1:0])
            2'b01:   load_word_assembled = {dmem_read_data[7:0],  dmem_data_buf[31:8]};
            2'b10:   load_word_assembled = {dmem_read_data[15:0], dmem_data_buf[31:16]};
            2'b11:   load_word_assembled = {dmem_read_data[23:0], dmem_data_buf[31:24]};
            default: load_word_assembled = dmem_read_data;   // aligned
        endcase
    end

    always @(*) begin
        case (funct3)
            F3_LB:   load_data_formatted = {{24{load_byte[7]}}, load_byte};
            F3_LBU:  load_data_formatted = {24'b0, load_byte};
            F3_LH:   load_data_formatted = {{16{load_half_assembled[15]}}, load_half_assembled};
            F3_LHU:  load_data_formatted = {16'b0, load_half_assembled};
            default: load_data_formatted = load_word_assembled;
        endcase
    end

    assign write_back_data = mem_to_reg ? load_data_formatted
                                        : (jump ? pc_plus4 : alu_result_reg);

    // --------------------------------------------------------
    // Data memory connections — fully misalignment-aware
    //
    // First pass  (in_second_pass=0): access word N = {alu_result_reg[31:2], 2'b00}
    // Second pass (in_second_pass=1): access word N+1 = word_N_addr + 4
    //
    // Byte enables use a barrel-shift pattern:
    //   F3_SB / lb*: 4'b0001 shifted left by off (single byte, never crosses)
    //   F3_SH / lh*: 4'b0011 shifted left by off (first pass), overflowed byte in second pass
    //   F3_SW / lw:  4'b1111 shifted left by off (first pass), remaining bytes in second pass
    //
    // For loads the memory ignores byte_enable and returns the full word;
    // we always set 4'b1111 for loads to avoid confusion.
    // --------------------------------------------------------

    logic [1:0] off;
    assign off = alu_result_reg[1:0];   // byte offset within word

    // DMEM address: word-aligned, +4 in second pass
    logic [31:0] dmem_word_base;
    assign dmem_word_base = {alu_result_reg[31:2], 2'b00};

    always @(*) begin
        dmem_addr = in_second_pass ? (dmem_word_base + 32'd4) : dmem_word_base;
    end

    assign dmem_write_en = mem_write;
    assign dmem_read_en  = mem_read;
    assign branch_eq     = (rs1_data == rs2_data);
    assign branch_lt     = ($signed(rs1_data) < $signed(rs2_data));
    assign branch_ltu    = (rs1_data < rs2_data);

    // Store write data — barrel-shifted to the correct byte lanes
    always @(*) begin
        if (in_second_pass) begin
            // Second pass: high bytes of rs2 shifted into the low lanes of word N+1
            case (funct3)
                F3_SH:   dmem_write_data = {24'b0, rs2_data[15:8]};               // off==3 only
                F3_SW: case (off)
                    2'b01: dmem_write_data = {24'b0, rs2_data[31:24]};
                    2'b10: dmem_write_data = {16'b0, rs2_data[31:16]};
                    default: dmem_write_data = {8'b0,  rs2_data[31:8]};            // off==3
                endcase
                default: dmem_write_data = rs2_data;
            endcase
        end else begin
            // First pass: rs2 data shifted left by off bytes
            case (funct3)
                F3_SB: dmem_write_data = {4{rs2_data[7:0]}};
                F3_SH: case (off)
                    2'b00: dmem_write_data = {2{rs2_data[15:0]}};
                    2'b01: dmem_write_data = {8'b0,  rs2_data[15:0], 8'b0};
                    2'b10: dmem_write_data = {rs2_data[15:0], 16'b0};
                    default: dmem_write_data = {rs2_data[7:0], 24'b0};             // off==3
                endcase
                default: case (off)  // F3_SW
                    2'b00: dmem_write_data = rs2_data;
                    2'b01: dmem_write_data = {rs2_data[23:0], 8'b0};
                    2'b10: dmem_write_data = {rs2_data[15:0], 16'b0};
                    default: dmem_write_data = {rs2_data[7:0], 24'b0};             // off==3
                endcase
            endcase
        end
    end

    // Byte enables
    always @(*) begin
        if (in_second_pass) begin
            // Second pass: remaining bytes in word N+1
            case (funct3)
                F3_SH:   dmem_byte_enable = 4'b0001;                              // sh off==3: 1 byte
                F3_SW: case (off)
                    2'b01: dmem_byte_enable = 4'b0001;
                    2'b10: dmem_byte_enable = 4'b0011;
                    default: dmem_byte_enable = 4'b0111;                           // off==3: 3 bytes
                endcase
                default: dmem_byte_enable = 4'b1111;                              // loads: full word
            endcase
        end else begin
            // First pass: bytes starting at offset off within word N
            case (funct3)
                F3_SB:   dmem_byte_enable = 4'b0001 << off;
                F3_SH:   dmem_byte_enable = (4'b0011 << off) & 4'b1111;
                F3_SW:   dmem_byte_enable = (4'b1111 << off) & 4'b1111;
                default: dmem_byte_enable = 4'b1111;                              // loads: full word
            endcase
        end
    end

endmodule
