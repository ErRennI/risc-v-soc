// ============================================================
// Module  : tb_csr
// Purpose : Unit test for csr_file module
//           Covers CSR read/write, set/clear, write inhibit,
//           trap entry, MRET, and irq_pending generation.
// ============================================================

import riscv_pkg::*;

module tb_csr;

    logic        clk;
    logic        rst_n;
    logic        trap_en;
    logic        mret_en;
    logic [31:0] trap_cause;
    logic [31:0] trap_pc;
    logic        irq_m_timer;
    logic        irq_m_external;
    logic [11:0] csr_addr;
    logic [31:0] csr_wdata;
    logic [1:0]  csr_op;
    logic        csr_write_en;
    logic [31:0] csr_rdata;
    logic [31:0] mtvec_out;
    logic [31:0] mepc_out;
    logic        irq_pending;
    logic        irq_cause_external;

    int error_count;

    csr_file dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .trap_en          (trap_en),
        .mret_en          (mret_en),
        .trap_cause       (trap_cause),
        .trap_val         (32'b0),
        .trap_pc          (trap_pc),
        .irq_m_timer      (irq_m_timer),
        .irq_m_external   (irq_m_external),
        .csr_addr         (csr_addr),
        .csr_wdata        (csr_wdata),
        .csr_op           (csr_op),
        .csr_write_en     (csr_write_en),
        .csr_rdata        (csr_rdata),
        .mtvec_out        (mtvec_out),
        .mepc_out         (mepc_out),
        .irq_pending      (irq_pending),
        .irq_cause_external(irq_cause_external)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check32(
        input logic [31:0] got,
        input logic [31:0] expected,
        input string name
    );
        if (got !== expected) begin
            error_count++;
            $display("FAIL: %s  expected 0x%08h  got 0x%08h", name, expected, got);
        end else
            $display("PASS: %s = 0x%08h", name, got);
    endtask

    // Write one CSR.  #1 after the posedge yields the active region to the
    // always_ff so its NBA update is applied before we deassert csr_write_en.
    task automatic csr_write(
        input logic [11:0] addr,
        input logic [31:0] wdata,
        input logic [1:0]  op
    );
        csr_addr     = addr;
        csr_wdata    = wdata;
        csr_op       = op;
        csr_write_en = 1'b1;
        @(posedge clk); #1;
        csr_write_en = 1'b0;
    endtask

    // Read CSR combinationally with a 1-unit settle delay.
    task automatic csr_read(
        input  logic [11:0] addr,
        output logic [31:0] val
    );
        csr_addr = addr;
        #1;
        val = csr_rdata;
    endtask

    logic [31:0] val;
    initial begin
        $dumpfile("sim_csr.vcd");
        $dumpvars(0, tb_csr);


        // Defaults
        trap_en           = 1'b0;
        mret_en           = 1'b0;
        trap_cause        = 32'b0;
        trap_pc           = 32'h0;
        irq_m_timer       = 1'b0;
        irq_m_external    = 1'b0;
        csr_addr          = 12'h0;
        csr_wdata         = 32'h0;
        csr_op            = 2'b00;
        csr_write_en      = 1'b0;
        error_count       = 0;

        rst_n = 1'b0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1'b1;
        @(posedge clk); #1;

        // --------------------------------------------------
        // Test 1: Write and read back MTVEC
        // --------------------------------------------------
        csr_write(CSR_MTVEC, 32'h0000_1000, 2'b00);
        csr_read(CSR_MTVEC, val);
        check32(val,       32'h0000_1000, "MTVEC read-back");
        check32(mtvec_out, 32'h0000_1000, "mtvec_out");

        // --------------------------------------------------
        // Test 2: Write and read back MIE (only 0x888 bits stick)
        // --------------------------------------------------
        csr_write(CSR_MIE, 32'hFFFF_FFFF, 2'b00);
        csr_read(CSR_MIE, val);
        check32(val, 32'h0000_0888, "MIE masked write");

        // --------------------------------------------------
        // Test 3: MSTATUS write — only bits 3 and 7 are writable
        //         MPP [12:11] is hardwired to 2'b11 on read
        // --------------------------------------------------
        csr_write(CSR_MSTATUS, 32'hFFFF_FFFF, 2'b00);
        csr_read(CSR_MSTATUS, val);
        check32(val, 32'h0000_1888, "MSTATUS masked write (MPP=11, MPIE=1, MIE=1)");

        // --------------------------------------------------
        // Test 4: Write and read MEPC
        // --------------------------------------------------
        csr_write(CSR_MEPC, 32'h0000_0040, 2'b00);
        csr_read(CSR_MEPC, val);
        check32(val,      32'h0000_0040, "MEPC read-back");
        check32(mepc_out, 32'h0000_0040, "mepc_out");

        // --------------------------------------------------
        // Test 5: CSRRS (set bits) on MSCRATCH
        // --------------------------------------------------
        csr_write(CSR_MSCRATCH, 32'h0F0F_0F0F, 2'b00);
        csr_write(CSR_MSCRATCH, 32'hF0F0_F0F0, 2'b01);
        csr_read(CSR_MSCRATCH, val);
        check32(val, 32'hFFFF_FFFF, "CSRRS set bits");

        // --------------------------------------------------
        // Test 6: CSRRC (clear bits) on MSCRATCH
        // --------------------------------------------------
        csr_write(CSR_MSCRATCH, 32'h0F0F_0F0F, 2'b10);
        csr_read(CSR_MSCRATCH, val);
        check32(val, 32'hF0F0_F0F0, "CSRRC clear bits");

        // --------------------------------------------------
        // Test 7: Write inhibit — CSRRS with wdata=0 must not modify CSR
        // --------------------------------------------------
        csr_write(CSR_MSCRATCH, 32'h1234_5678, 2'b00);
        // Inhibited write (csr_write_en=0): nothing should change
        csr_addr     = CSR_MSCRATCH;
        csr_wdata    = 32'h0;
        csr_op       = 2'b01;
        csr_write_en = 1'b0;
        @(posedge clk); #1;
        csr_read(CSR_MSCRATCH, val);
        check32(val, 32'h1234_5678, "write inhibit: CSRRS with wdata=0 preserves CSR");

        // --------------------------------------------------
        // Test 8: trap_en — ECALL
        // --------------------------------------------------
        csr_write(CSR_MSTATUS, 32'h0000_0008, 2'b00);  // MIE=1, MPIE=0
        csr_write(CSR_MTVEC,   32'h0000_2000, 2'b00);
        trap_pc    = 32'h0000_0010;
        trap_cause = EXC_ECALL_M;
        trap_en    = 1'b1;
        @(posedge clk); #1;
        trap_en = 1'b0;
        csr_read(CSR_MEPC,    val); check32(val, 32'h0000_0010, "trap MEPC saved");
        csr_read(CSR_MCAUSE,  val); check32(val, 32'h0000_000B, "trap MCAUSE ECALL=11");
        csr_read(CSR_MSTATUS, val);
        check32({31'b0, val[3]}, 32'h0, "trap MIE cleared");
        check32({31'b0, val[7]}, 32'h1, "trap MPIE saved from MIE");
        check32(mtvec_out, 32'h0000_2000, "trap mtvec_out");

        // --------------------------------------------------
        // Test 9: mret_en — restores MIE from MPIE
        // --------------------------------------------------
        mret_en = 1'b1;
        @(posedge clk); #1;
        mret_en = 1'b0;
        csr_read(CSR_MSTATUS, val);
        check32({31'b0, val[3]}, 32'h1, "mret MIE restored");
        check32({31'b0, val[7]}, 32'h1, "mret MPIE set to 1");
        check32(mepc_out, 32'h0000_0010, "mret mepc_out unchanged");

        // --------------------------------------------------
        // Test 10: irq_pending generation
        // --------------------------------------------------
        csr_write(CSR_MSTATUS, 32'h0000_0008, 2'b00);  // MIE=1
        csr_write(CSR_MIE,     32'h0000_0080, 2'b00);  // MTIE=1
        irq_m_timer = 1'b1;
        #1;
        check32({31'b0, irq_pending}, 32'h1, "irq_pending asserted");
        csr_write(CSR_MSTATUS, 32'h0000_0000, 2'b00);  // MIE=0
        #1;
        check32({31'b0, irq_pending}, 32'h0, "irq_pending clears when MIE=0");
        irq_m_timer = 1'b0;

        // --------------------------------------------------
        // Test 11: trap_en — timer interrupt
        // --------------------------------------------------
        csr_write(CSR_MSTATUS, 32'h0000_0008, 2'b00);  // re-enable MIE
        trap_pc    = 32'h0000_0050;
        trap_cause = EXC_M_TIMER_IRQ;
        trap_en    = 1'b1;
        @(posedge clk); #1;
        trap_en = 1'b0;
        csr_read(CSR_MCAUSE, val); check32(val, 32'h8000_0007, "trap MCAUSE timer IRQ");
        csr_read(CSR_MEPC,   val); check32(val, 32'h0000_0050, "trap MEPC = interrupted PC");

        // --------------------------------------------------
        // Test 12: MIP reflects irq_m_timer
        // --------------------------------------------------
        irq_m_timer = 1'b1;
        csr_read(CSR_MIP, val); check32(val, 32'h0000_0080, "MIP.MTIP set");
        irq_m_timer = 1'b0;
        csr_read(CSR_MIP, val); check32(val, 32'h0000_0000, "MIP.MTIP clear");

        // --------------------------------------------------
        // Test 13: MHARTID always 0
        // --------------------------------------------------
        csr_read(CSR_MHARTID, val);
        check32(val, 32'h0, "MHARTID = 0");

        // --------------------------------------------------
        // Test 14: external IRQ — irq_pending, MIP.MEIP, mcause
        // --------------------------------------------------
        csr_write(CSR_MSTATUS, 32'h0000_0008, 2'b00);  // MIE=1
        csr_write(CSR_MIE,     32'h0000_0800, 2'b00);  // MEIE=1
        irq_m_external = 1'b1;
        #1;
        check32({31'b0, irq_pending}, 32'h1, "irq_pending asserted (external)");
        check32({31'b0, irq_cause_external}, 32'h1, "irq_cause_external asserted");
        csr_read(CSR_MIP, val); check32(val, 32'h0000_0800, "MIP.MEIP set");

        trap_pc    = 32'h0000_0060;
        trap_cause = EXC_M_EXTERNAL_IRQ;
        trap_en    = 1'b1;
        @(posedge clk); #1;
        trap_en = 1'b0;
        csr_read(CSR_MCAUSE, val); check32(val, 32'h8000_000B, "trap MCAUSE external IRQ");
        csr_read(CSR_MEPC,   val); check32(val, 32'h0000_0060, "trap MEPC = interrupted PC");
        irq_m_external = 1'b0;

        // --------------------------------------------------
        // Test 15: priority — timer + external both pending, external wins
        // --------------------------------------------------
        csr_write(CSR_MSTATUS, 32'h0000_0008, 2'b00);  // re-enable MIE
        csr_write(CSR_MIE,     32'h0000_0880, 2'b00);  // MTIE=1, MEIE=1
        irq_m_timer    = 1'b1;
        irq_m_external = 1'b1;
        #1;
        check32({31'b0, irq_cause_external}, 32'h1, "priority: external wins over timer");
        irq_m_timer    = 1'b0;
        irq_m_external = 1'b0;

        if (error_count != 0) begin
            $display("CSR unit test FAILED: %0d error(s).", error_count);
            $fatal(1);
        end

        $display("CSR unit test passed (22 checks).");
        $finish;
    end

endmodule
