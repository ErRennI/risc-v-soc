// ============================================================
// File    : riscv_pkg.sv
// Purpose : RISC-V RV32IM constant definitions
//           Opcodes, funct3, funct7 values for instruction decode
// ============================================================

package riscv_pkg;

    // --------------------------------------------------------
    // Opcodes — bits [6:0] of every instruction
    // --------------------------------------------------------
    parameter logic [6:0] OP_R       = 7'b0110011; // R-type: ADD, SUB, AND, OR...
    parameter logic [6:0] OP_I_ALU   = 7'b0010011; // I-type: ADDI, ANDI, ORI...
    parameter logic [6:0] OP_I_LOAD  = 7'b0000011; // I-type: LW, LH, LB
    parameter logic [6:0] OP_S       = 7'b0100011; // S-type: SW, SH, SB
    parameter logic [6:0] OP_B       = 7'b1100011; // B-type: BEQ, BNE, BLT...
    parameter logic [6:0] OP_JAL     = 7'b1101111; // J-type: JAL
    parameter logic [6:0] OP_JALR    = 7'b1100111; // I-type: JALR
    parameter logic [6:0] OP_LUI     = 7'b0110111; // U-type: LUI
    parameter logic [6:0] OP_AUIPC   = 7'b0010111; // U-type: AUIPC
    parameter logic [6:0] OP_SYSTEM  = 7'b1110011; // I-type: ECALL, EBREAK, CSR
    parameter logic [6:0] OP_FENCE   = 7'b0001111; // FENCE / FENCE.I — NOP for in-order CPU

    // --------------------------------------------------------
    // funct3 values — bits [14:12]
    // Used together with opcode to identify exact instruction
    // --------------------------------------------------------

    // funct3 for R-type and I-type ALU operations
    parameter logic [2:0] F3_ADD_SUB = 3'b000; // ADD, SUB, ADDI
    parameter logic [2:0] F3_SLL     = 3'b001; // SLL, SLLI
    parameter logic [2:0] F3_SLT     = 3'b010; // SLT, SLTI
    parameter logic [2:0] F3_SLTU    = 3'b011; // SLTU, SLTIU
    parameter logic [2:0] F3_XOR     = 3'b100; // XOR, XORI
    parameter logic [2:0] F3_SR      = 3'b101; // SRL, SRA, SRLI, SRAI
    parameter logic [2:0] F3_OR      = 3'b110; // OR, ORI
    parameter logic [2:0] F3_AND     = 3'b111; // AND, ANDI

    // funct3 for branch instructions
    parameter logic [2:0] F3_BEQ     = 3'b000; // Branch if Equal
    parameter logic [2:0] F3_BNE     = 3'b001; // Branch if Not Equal
    parameter logic [2:0] F3_BLT     = 3'b100; // Branch if Less Than
    parameter logic [2:0] F3_BGE     = 3'b101; // Branch if Greater or Equal
    parameter logic [2:0] F3_BLTU    = 3'b110; // Branch if Less Than Unsigned
    parameter logic [2:0] F3_BGEU    = 3'b111; // Branch if Greater or Equal Unsigned

    // funct3 for load instructions
    parameter logic [2:0] F3_LW      = 3'b010; // Load Word (32-bit)
    parameter logic [2:0] F3_LH      = 3'b001; // Load Halfword (16-bit)
    parameter logic [2:0] F3_LB      = 3'b000; // Load Byte (8-bit)
    parameter logic [2:0] F3_LHU     = 3'b101; // Load Halfword Unsigned (16-bit)
    parameter logic [2:0] F3_LBU     = 3'b100; // Load Byte Unsigned (8-bit)

    // funct3 for store instructions
    parameter logic [2:0] F3_SW      = 3'b010; // Store Word (32-bit)
    parameter logic [2:0] F3_SH      = 3'b001; // Store Halfword (16-bit)
    parameter logic [2:0] F3_SB      = 3'b000; // Store Byte (8-bit)

    // --------------------------------------------------------
    // funct7 values — bits [31:25]
    // Only used for R-type instructions to distinguish
    // ADD vs SUB and SRL vs SRA
    // --------------------------------------------------------
    parameter logic [6:0] F7_NORMAL  = 7'b0000000; // ADD, SRL, and most R-type
    parameter logic [6:0] F7_ALT     = 7'b0100000; // SUB, SRA
    parameter logic [6:0] F7_MEXT    = 7'b0000001; // RV32M: MUL, DIV, REM

    // --------------------------------------------------------
    // FSM State definitions
    // --------------------------------------------------------
    parameter logic [2:0] STATE_FETCH     = 3'b000;
    parameter logic [2:0] STATE_DECODE    = 3'b001;
    parameter logic [2:0] STATE_EXECUTE   = 3'b010;
    parameter logic [2:0] STATE_MEMORY    = 3'b011;
    parameter logic [2:0] STATE_WRITEBACK = 3'b100;
    parameter logic [2:0] STATE_MDU       = 3'b101;  // multi-cycle mul/div wait
    parameter logic [2:0] STATE_TRAP      = 3'b110;  // trap entry: save PC/cause, jump to MTVEC
    parameter logic [2:0] STATE_MEMORY2   = 3'b111;  // second DMEM access for cross-boundary misaligned

    // --------------------------------------------------------
    // MCAUSE exception / interrupt codes
    // --------------------------------------------------------
    parameter logic [31:0] EXC_FETCH_MISALIGN  = 32'h00000000; // instruction address misaligned
    parameter logic [31:0] EXC_ILLEGAL_INSTR  = 32'h00000002; // illegal instruction
    parameter logic [31:0] EXC_EBREAK         = 32'h00000003; // breakpoint
    parameter logic [31:0] EXC_LOAD_MISALIGN  = 32'h00000004; // load address misaligned
    parameter logic [31:0] EXC_STORE_MISALIGN = 32'h00000006; // store address misaligned
    parameter logic [31:0] EXC_ECALL_M        = 32'h0000000B; // ECALL from M-mode
    parameter logic [31:0] EXC_M_TIMER_IRQ    = 32'h80000007; // machine timer interrupt
    parameter logic [31:0] EXC_M_EXTERNAL_IRQ = 32'h8000000B; // machine external interrupt (MEIP)

    // --------------------------------------------------------
    // CSR addresses (machine-level)
    // --------------------------------------------------------
    parameter logic [11:0] CSR_MSTATUS   = 12'h300;
    parameter logic [11:0] CSR_MIE       = 12'h304;
    parameter logic [11:0] CSR_MTVEC     = 12'h305;
    parameter logic [11:0] CSR_MSCRATCH  = 12'h340;
    parameter logic [11:0] CSR_MEPC      = 12'h341;
    parameter logic [11:0] CSR_MCAUSE    = 12'h342;
    parameter logic [11:0] CSR_MTVAL     = 12'h343;
    parameter logic [11:0] CSR_MIP       = 12'h344;
    parameter logic [11:0] CSR_MHARTID   = 12'hF14;
    parameter logic [11:0] CSR_CYCLE     = 12'hC00;  // read-only: cycle counter
    parameter logic [11:0] CSR_INSTRET   = 12'hC02;  // read-only: retired instruction counter

endpackage
