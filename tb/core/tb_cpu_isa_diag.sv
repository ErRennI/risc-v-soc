// ============================================================
// Module  : tb_cpu_isa_diag
// Purpose : CPU-level regression using compiled ISA diagnostic
//           software. The program writes pass/fail signatures
//           into DMEM so the bench can stop deterministically.
// ============================================================

module tb_cpu_isa_diag;

    // --- Signature constants ---
    localparam logic [31:0] STATUS_ADDR = 32'h2000_0000;
    localparam logic [31:0] DETAIL_ADDR = 32'h2000_0004;
    localparam logic [31:0] PASS_SIG    = 32'h1A5A1A5A;
    localparam logic [31:0] FAIL_SIG    = 32'h0BAD0BAD;

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

    logic [31:0] imem [0:8191];
    logic [31:0] dmem [0:8191];
    int cycle_count;

    // --- Instantiate CPU ---
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

    // --- Simple memory model ---
    assign imem_data = imem[imem_addr[14:2]];
    assign dmem_read_data = (dmem_addr[31:28] == 4'h2) ? dmem[dmem_addr[14:2]] : 32'h0000_0000;

    always_ff @(posedge clk) begin
        if (dmem_write_en && dmem_addr[31:28] == 4'h2) begin
            if (dmem_byte_enable[0]) dmem[dmem_addr[14:2]][7:0]   <= dmem_write_data[7:0];
            if (dmem_byte_enable[1]) dmem[dmem_addr[14:2]][15:8]  <= dmem_write_data[15:8];
            if (dmem_byte_enable[2]) dmem[dmem_addr[14:2]][23:16] <= dmem_write_data[23:16];
            if (dmem_byte_enable[3]) dmem[dmem_addr[14:2]][31:24] <= dmem_write_data[31:24];
        end
    end

    integer i;
    initial begin
        $dumpfile("sim_cpu_isa.vcd");
        $dumpvars(0, tb_cpu_isa_diag);


        for (i = 0; i < 8192; i = i + 1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 32'h00000000;
        end

        // Load compiled ISA diagnostic image
        $readmemh("sw/tests/isa_diag.mem", imem);

        rst_n = 1'b0;
        cycle_count = 0;

        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;

        // Run until PASS, FAIL, or timeout
        while (cycle_count < 4000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            if (dmem[STATUS_ADDR[14:2]] == PASS_SIG) begin
                if (dmem[DETAIL_ADDR[14:2]] !== 32'h0000_0000) begin
                    $display("FAIL: ISA diagnostic detail expected 0, got 0x%08h", dmem[DETAIL_ADDR[14:2]]);
                    $fatal(1);
                end
                $display("PASS: ISA diagnostic signature observed after %0d cycles", cycle_count);
                $finish;
            end

            if (dmem[STATUS_ADDR[14:2]] == FAIL_SIG) begin
                $display("FAIL: ISA diagnostic failed with code %0d (0x%08h)",
                    dmem[DETAIL_ADDR[14:2]], dmem[DETAIL_ADDR[14:2]]);
                $fatal(1);
            end
        end

        $display("FAIL: ISA diagnostic timed out after %0d cycles", cycle_count);
        $fatal(1);
    end

endmodule
