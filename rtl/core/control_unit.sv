// ============================================================
// Module  : control_unit
// Purpose : Multi-cycle FSM control unit for RV32IM
//           Decodes instructions and drives all control signals
//           States: FETCH, DECODE, EXECUTE, MEMORY, WRITEBACK,
//                   MDU, TRAP
// ============================================================

import riscv_pkg::*;
import alu_ops::*;

module control_unit (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] instruction,
    input  logic        branch_eq,
    input  logic        branch_lt,
    input  logic        branch_ltu,
    input  logic        mdu_done,             // HIGH for one cycle when MDU result is ready
    input  logic        irq_pending,          // HIGH when a timer or external IRQ is enabled and pending
    input  logic        irq_cause_external,   // HIGH when the pending IRQ is external, not timer
    input  logic        mem_addr_misaligned,   // HIGH in EXECUTE when load/store addr is unaligned
    input  logic        fetch_addr_misaligned, // HIGH in EXECUTE when branch/JAL/JALR target is unaligned

    output logic [1:0]  alu_src_a_sel,
    output logic [4:0]  alu_operation,
    output logic        alu_src_b,
    output logic        reg_write,
    output logic        mem_read,
    output logic        mem_write,
    output logic        mem_to_reg,
    output logic        jump,
    output logic [1:0]  pc_src,
    output logic        instr_latch_en,   // HIGH in STATE_DECODE — latches synchronous IMEM output
    output logic        pc_write_en,      // HIGH when PC should update
    output logic        alu_reg_en,       // HIGH when ALU result reg should capture
    output logic        mdu_start,        // HIGH for one cycle to launch the MDU
    output logic        trap_en,          // HIGH in STATE_TRAP: save PC/cause, jump to MTVEC
    output logic        mret_en,          // HIGH in STATE_EXECUTE for MRET: PC=MEPC
    output logic        csr_reg_en,       // HIGH in STATE_EXECUTE for CSR: capture old CSR value
    output logic        csr_write_en,     // HIGH in STATE_EXECUTE for CSR: write new value
    output logic [31:0] trap_cause,       // MCAUSE value (valid during STATE_TRAP)
    output logic        in_second_pass,   // HIGH in STATE_MEMORY2 (second DMEM cycle)
    output logic        instret_en        // HIGH in the cycle an instruction retires
);

    // Detect RV32M instructions (R-type with funct7 = MEXT).
    logic is_m_op;
    assign is_m_op = (instruction[6:0] == OP_R) && (instruction[31:25] == F7_MEXT);

    // --------------------------------------------------------
    // Instruction field extraction
    // --------------------------------------------------------
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic       branch_taken;

    assign opcode = instruction[6:0];
    assign funct3 = instruction[14:12];
    assign funct7 = instruction[31:25];

    // CSRRS/CSRRC(/I) write is inhibited when rs1/zimm == 0 (instruction[13] = funct3[1]).
    logic csr_no_write;
    assign csr_no_write = instruction[13] && (instruction[19:15] == 5'b0);

    // Valid opcode set — any opcode NOT in this set is an illegal instruction.
    logic is_valid_opcode;
    assign is_valid_opcode = (opcode == OP_R)     || (opcode == OP_I_ALU) ||
                             (opcode == OP_I_LOAD) || (opcode == OP_S)    ||
                             (opcode == OP_B)      || (opcode == OP_JAL)  ||
                             (opcode == OP_JALR)   || (opcode == OP_LUI)  ||
                             (opcode == OP_AUIPC)  || (opcode == OP_SYSTEM) ||
                             (opcode == OP_FENCE);

    // --------------------------------------------------------
    // Branch condition logic
    // --------------------------------------------------------
    always @(*) begin
        branch_taken = 1'b0;
        case (funct3)
            F3_BEQ:  branch_taken = branch_eq;
            F3_BNE:  branch_taken = ~branch_eq;
            F3_BLT:  branch_taken = branch_lt;
            F3_BGE:  branch_taken = ~branch_lt;
            F3_BLTU: branch_taken = branch_ltu;
            F3_BGEU: branch_taken = ~branch_ltu;
            default: branch_taken = 1'b0;
        endcase
    end

    // --------------------------------------------------------
    // FSM state register
    // --------------------------------------------------------
    logic [2:0] current_state;
    logic [2:0] next_state;

    always_ff @(posedge clk) begin
        if (rst_n == 0)
            current_state <= STATE_FETCH;
        else
            current_state <= next_state;
    end

    // Registered trap cause — set one cycle before STATE_TRAP is entered
    // so csr_file sees a stable value when it latches at STATE_TRAP.
    logic [31:0] trap_cause_reg;

    // Latch misaligned_cross from EXECUTE so it stays stable in STATE_MEMORY / STATE_MEMORY2.
    // mem_addr_misaligned is combinational from alu_result (valid only in STATE_EXECUTE).
    logic misaligned_cross_reg;

    always_ff @(posedge clk) begin
        if (!rst_n)
            misaligned_cross_reg <= 1'b0;
        else if (current_state == STATE_EXECUTE)
            misaligned_cross_reg <= mem_addr_misaligned;
    end

    always_ff @(posedge clk) begin
        if (!rst_n)
            trap_cause_reg <= 32'b0;
        else case (current_state)
            STATE_FETCH:
                if (irq_pending)
                    trap_cause_reg <= irq_cause_external ? EXC_M_EXTERNAL_IRQ : EXC_M_TIMER_IRQ;
            STATE_EXECUTE:
                case (opcode)
                    OP_SYSTEM:
                        if (funct3 == 3'b000 && instruction[31:20] != 12'h302) begin
                            if (instruction[31:20] == 12'h001)
                                trap_cause_reg <= EXC_EBREAK;
                            else
                                trap_cause_reg <= EXC_ECALL_M;
                        end
                    OP_B:
                        if (branch_taken && fetch_addr_misaligned)
                            trap_cause_reg <= EXC_FETCH_MISALIGN;
                    OP_JAL, OP_JALR:
                        if (fetch_addr_misaligned)
                            trap_cause_reg <= EXC_FETCH_MISALIGN;
                    // OP_I_LOAD and OP_S: hardware handles misalignment — no trap
                    default:
                        if (!is_valid_opcode)
                            trap_cause_reg <= EXC_ILLEGAL_INSTR;
                endcase
            default: ;
        endcase
    end

    // --------------------------------------------------------
    // FSM next state logic
    // --------------------------------------------------------

    always @(*) begin
        case (current_state)
            STATE_FETCH: begin
                // Interrupt delivery happens at instruction boundaries.
                next_state = irq_pending ? STATE_TRAP : STATE_DECODE;
            end

            STATE_DECODE:   next_state = STATE_EXECUTE;

            STATE_EXECUTE:  begin
                case (opcode)
                    OP_I_LOAD: next_state = STATE_MEMORY;   // hardware handles misalignment
                    OP_S:      next_state = STATE_MEMORY;
                    OP_B:      next_state = (branch_taken && fetch_addr_misaligned) ? STATE_TRAP : STATE_FETCH;
                    OP_JAL, OP_JALR: next_state = fetch_addr_misaligned ? STATE_TRAP : STATE_WRITEBACK;
                    OP_R:                   next_state = is_m_op ? STATE_MDU : STATE_WRITEBACK;
                    OP_I_ALU:               next_state = STATE_WRITEBACK;
                    OP_LUI:                 next_state = STATE_WRITEBACK;
                    OP_AUIPC:               next_state = STATE_WRITEBACK;
                    OP_SYSTEM: begin
                        case (funct3)
                            3'b000: begin
                                if (instruction[31:20] == 12'h302)
                                    next_state = STATE_FETCH;    // MRET: done in EXECUTE
                                else
                                    next_state = STATE_TRAP;     // ECALL / EBREAK
                            end
                            default: next_state = STATE_WRITEBACK; // CSR instructions
                        endcase
                    end
                    OP_FENCE:  next_state = STATE_FETCH;           // NOP for in-order CPU
                    default:   next_state = STATE_TRAP;            // illegal instruction
                endcase
            end

            STATE_MEMORY: begin
                case (opcode)
                    OP_I_LOAD: next_state = misaligned_cross_reg ? STATE_MEMORY2 : STATE_WRITEBACK;
                    OP_S:      next_state = misaligned_cross_reg ? STATE_MEMORY2 : STATE_FETCH;
                    default:   next_state = STATE_FETCH;
                endcase
            end

            STATE_MEMORY2: begin
                case (opcode)
                    OP_I_LOAD: next_state = STATE_WRITEBACK;
                    default:   next_state = STATE_FETCH;
                endcase
            end

            STATE_MDU:       next_state = mdu_done ? STATE_WRITEBACK : STATE_MDU;
            STATE_WRITEBACK: next_state = STATE_FETCH;
            STATE_TRAP:      next_state = STATE_FETCH;
            default:         next_state = STATE_FETCH;
        endcase
    end

    // --------------------------------------------------------
    // Output logic (control signal generation)
    // --------------------------------------------------------

    always @(*) begin
        alu_operation   = ALU_ADD;
        alu_src_a_sel   = 2'b00;
        alu_src_b       = 0;
        reg_write       = 0;
        mem_read        = 0;
        mem_write       = 0;
        mem_to_reg      = 0;
        jump            = 0;
        instr_latch_en  = 0;
        pc_write_en     = 0;
        alu_reg_en      = 0;
        mdu_start       = 0;
        pc_src          = 2'b00;
        trap_en         = 0;
        mret_en         = 0;
        csr_reg_en      = 0;
        csr_write_en    = 0;
        trap_cause      = trap_cause_reg;
        in_second_pass  = 0;
        instret_en      = 0;

        case (current_state)
            STATE_FETCH:    instr_latch_en = 0;
            STATE_DECODE:   instr_latch_en = 1;

            STATE_EXECUTE: begin
                alu_reg_en = ~is_m_op;  // default for non-M, non-CSR, non-ECALL ops
                case (opcode)
                    OP_R: begin
                        if (funct7 == F7_MEXT) begin
                            mdu_start = 1'b1;
                            case (funct3)
                                3'b000:  alu_operation = ALU_MUL;
                                3'b001:  alu_operation = ALU_MULH;
                                3'b010:  alu_operation = ALU_MULHSU;
                                3'b011:  alu_operation = ALU_MULHU;
                                3'b100:  alu_operation = ALU_DIV;
                                3'b101:  alu_operation = ALU_DIVU;
                                3'b110:  alu_operation = ALU_REM;
                                3'b111:  alu_operation = ALU_REMU;
                                default: alu_operation = ALU_ADD;
                            endcase
                        end else begin
                            case (funct3)
                                F3_ADD_SUB: begin
                                    if (funct7 == F7_ALT)
                                        alu_operation = ALU_SUB;
                                    else
                                        alu_operation = ALU_ADD;
                                end
                                F3_AND:  alu_operation = ALU_AND;
                                F3_OR:   alu_operation = ALU_OR;
                                F3_XOR:  alu_operation = ALU_XOR;
                                F3_SLL:  alu_operation = ALU_SLL;
                                F3_SR: begin
                                    if (funct7 == F7_ALT)
                                        alu_operation = ALU_SRA;
                                    else
                                        alu_operation = ALU_SRL;
                                end
                                F3_SLT:  alu_operation = ALU_SLT;
                                F3_SLTU: alu_operation = ALU_SLTU;
                            endcase
                        end
                    end

                    OP_I_LOAD, OP_S: begin
                        alu_src_a_sel = 2'b00;
                        alu_src_b = 1;
                        alu_operation = ALU_ADD;
                    end

                    OP_B: begin
                        alu_src_a_sel = 2'b00;
                        alu_src_b = 0;
                        alu_operation = ALU_SUB;
                        // Suppress PC update when the taken target is misaligned so
                        // MEPC captures the branch instruction's PC, not the target.
                        if (!(branch_taken && fetch_addr_misaligned)) begin
                            pc_write_en = 1;
                            if (branch_taken)
                                pc_src = 2'b01;
                        end
                    end

                    OP_JAL: begin
                        jump = 1;
                        pc_src = 2'b11;
                    end

                    OP_JALR: begin
                        alu_src_a_sel = 2'b00;
                        jump = 1;
                        pc_src = 2'b10;
                    end

                    OP_LUI: begin
                        alu_src_a_sel = 2'b10;
                        alu_src_b = 1;
                        alu_operation = ALU_ADD;
                    end

                    OP_AUIPC: begin
                        alu_src_a_sel = 2'b01;
                        alu_src_b = 1;
                        alu_operation = ALU_ADD;
                    end

                    OP_SYSTEM: begin
                        alu_reg_en = 0;  // override ~is_m_op default
                        case (funct3)
                            3'b000: begin
                                if (instruction[31:20] == 12'h302) begin
                                    // MRET: restore MIE, jump to MEPC
                                    mret_en     = 1;
                                    pc_write_en = 1;
                                end
                                // ECALL: STATE_TRAP handles everything, no signals here
                            end
                            default: begin
                                // CSR instructions (CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI)
                                csr_reg_en   = 1;
                                csr_write_en = ~csr_no_write;
                            end
                        endcase
                    end

                    OP_FENCE: begin
                        alu_reg_en  = 0;
                        pc_write_en = 1;    // advance PC+4; pc_src defaults to 2'b00
                    end

                    default: begin
                        // Illegal instruction — ALU computes a dummy result (harmless).
                        // STATE_TRAP handles the trap; no register or memory writes occur.
                        alu_src_a_sel = 2'b00;
                        alu_src_b = 1;
                        case (funct3)
                            F3_ADD_SUB: alu_operation = ALU_ADD;
                            F3_AND:     alu_operation = ALU_AND;
                            F3_OR:      alu_operation = ALU_OR;
                            F3_XOR:     alu_operation = ALU_XOR;
                            F3_SLL:     alu_operation = ALU_SLL;
                            F3_SR: begin
                                if (funct7 == F7_ALT)
                                    alu_operation = ALU_SRA;
                                else
                                    alu_operation = ALU_SRL;
                            end
                            F3_SLT:     alu_operation = ALU_SLT;
                            F3_SLTU:    alu_operation = ALU_SLTU;
                            default:    alu_operation = ALU_ADD;
                        endcase
                    end
                endcase
            end

            STATE_MEMORY: begin
                case (opcode)
                    OP_I_LOAD: mem_read = 1;
                    OP_S: begin
                        mem_write   = 1;
                        // Defer PC update to STATE_MEMORY2 when cross-boundary store needs two cycles
                        pc_write_en = ~misaligned_cross_reg;
                    end
                endcase
            end

            STATE_MEMORY2: begin
                in_second_pass = 1;
                case (opcode)
                    OP_I_LOAD: mem_read = 1;    // second word read; result assembled in WRITEBACK
                    OP_S: begin
                        mem_write   = 1;
                        pc_write_en = 1;         // final store cycle
                    end
                endcase
            end

            STATE_WRITEBACK: begin
                pc_write_en = 1;
                case (opcode)
                    OP_I_LOAD: begin
                        reg_write  = 1;
                        mem_to_reg = 1;
                    end
                    OP_JAL: begin
                        reg_write = 1;
                        jump      = 1;
                        pc_src    = 2'b11;
                    end
                    OP_JALR: begin
                        reg_write = 1;
                        jump      = 1;
                        pc_src    = 2'b10;
                    end
                    default: begin
                        reg_write  = 1;
                        mem_to_reg = 0;
                    end
                endcase
            end

            STATE_TRAP: begin
                // Save faulting/interrupted PC to MEPC, write MCAUSE/MTVAL,
                // clear MIE, redirect PC to MTVEC.
                trap_en     = 1;
                pc_write_en = 1;
                // trap_cause is driven from trap_cause_reg in the defaults above
            end
        endcase

        // An instruction retires whenever the PC advances, except during trap entry.
        instret_en = pc_write_en && (current_state != STATE_TRAP);
    end

endmodule
