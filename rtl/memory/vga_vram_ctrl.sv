module vga_vram_ctrl (
    input logic clk_100mhz,
    input logic clk_25mhz,
    input logic rst,  //25mhz gerek olmazsa sil

    //MMIO
    input logic vram_write_en,
    input logic vram_clear_en,  //clean screen
    input logic [12:0] cpu_addr,
    input logic [15:0] cpu_write_data,  //4 empty 4 bit color 8 bit characters ASCII
    output logic vram_ready,

    //Info that goes to VGA
    input  logic [12:0] vga_read_addr,
    output logic [ 7:0] char_code,
    output logic [ 3:0] char_color,
    output logic [ 3:0] char_attrib
);

    logic [15:0] mem[0:4799];

    typedef enum logic {
        STATE_IDLE,
        STATE_CLEAR
    } state_t;
    state_t current_state, next_state;

    logic [12:0] clear_cnt_reg, clear_cnt_next;

    logic actual_write_en;
    logic [12:0] actual_write_addr;
    logic [11:0] actual_write_data;

    always_ff @(posedge clk_100mhz or negedge rst) begin
        if (!rst) begin
            current_state <= STATE_IDLE;
            clear_cnt_reg <= 16'd0;
        end else begin
            current_state <= next_state;
            clear_cnt_reg <= clear_cnt_next;
        end
    end

    always_comb begin
        next_state = current_state;
        clear_cnt_next = clear_cnt_reg;
        vram_ready = 1'b1;

        case (current_state)
            STATE_IDLE: begin
                clear_cnt_next = 13'd0;
                if (vram_clear_en) begin
                    next_state = STATE_CLEAR;
                end
            end

            STATE_CLEAR: begin
                vram_ready = 1'b0;

                if (clear_cnt_reg == 13'd4799) begin
                    next_state = STATE_IDLE;
                end else begin
                    clear_cnt_next = clear_cnt_reg + 1'b1;
                end
            end
        endcase
    end

    always_comb begin
        if (current_state == STATE_CLEAR) begin
            actual_write_en   = 1'b1;
            actual_write_addr = clear_cnt_reg;
            actual_write_data = 16'h0020;
        end else begin
            actual_write_en   = vram_write_en;
            actual_write_addr = cpu_addr;
            actual_write_data = cpu_write_data;
        end
    end
    //Port B
    always_ff @(posedge clk_100mhz) begin
        if (actual_write_en) begin
            mem[actual_write_addr] <= actual_write_data;
        end
    end
    //Port A
    logic [15:0] vga_read_data;
    always_ff @(posedge clk_25mhz) begin
        vga_read_data <= mem[vga_read_addr];
    end

    assign char_attrib = vga_read_data[15:12];
    assign char_color = vga_read_data[11:8];
    assign char_code  = vga_read_data[7:0];
endmodule
