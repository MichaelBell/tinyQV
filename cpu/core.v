/* TinyQV: A RISC-V core designed to use minimal area.
  
   This core module takes decoded instructions and produces output data
 */

module tinyqv_core #(parameter NUM_REGS=16, parameter REG_ADDR_BITS=4) (
    input clk,
    input rstn,

    input [3:0] imm,
    input [11:0] imm_lo,

    input is_load,
    input is_alu_imm,
    input is_auipc,
    input is_store,
    input is_alu_reg,
    input is_lui,
    input is_branch,
    input is_jalr,
    input is_jal,
    input is_system,
    input is_interrupt,
    input is_stall,

    input [3:0] alu_op,  // See tinyqv_alu for format
    input [2:0] mem_op,

    input [REG_ADDR_BITS-1:0] rs1,
    input [REG_ADDR_BITS-1:0] rs2,
    input [REG_ADDR_BITS-1:0] rd,

    input [2:0] counter,    // Sub cycle counter, must increment on every clock
    input [3:0] pc,
    input [3:0] next_pc,
    input [3:0] data_in,
    input load_data_ready,

    output reg [3:0] data_out,  // Data for the active store instruction
    output [27:0] addr_out,
    output address_ready,   // The addr_out holds the address for the active load/store instruction
    output reg instr_complete,  // The current instruction will complete this clock, so the instruction may be updated.
                            // If no new instruction is available all a NOOP should be issued, which will complete in 1 cycle.
    output branch,          // addr_out holds the address to branch to
    
    output [23:1] return_addr, // On count 7 this is the low 24 bits of x1

    input [3:0] interrupt_req,
    output interrupt_pending,

    output       debug_reg_wen,
    output [3:0] debug_rd
);

    // Forward declarations
    wire last_count = (counter == 7);
    reg [1:0] cycle;

    wire is_shift = alu_op[1:0] == 2'b01;
    wire is_mul = alu_op[3:1] == 3'b101;
    wire is_czero = alu_op[3:1] == 3'b111;

    wire is_priv = is_system && (alu_op[2:0] == 3'b000);
    wire is_trap = is_priv && (imm_lo[9:8] == 2'b00);
    wire is_exception = is_trap || is_interrupt;
    wire is_mret = is_priv && (imm_lo[9:8] == 2'b11);
    reg [23:0] mepc;

    reg mstatus_mte;   // Trap enable - this is non-standard, but allows trapping without
                       //               double fault while interrupts are disabled.
    reg mstatus_mie;   // Interrupt enable
    reg mstatus_mpie;  // Prior interrupt enable (whether interrupts were enabled on entry to trap)

    wire is_csr = is_system && alu_op[1:0] != 2'b00;
    reg [3:0] csr_read;
    wire is_csr_write = is_csr && alu_op[1:0] == 2'b01;
    wire is_csr_set   = is_csr && alu_op[1:0] == 2'b10;
    wire is_csr_clear = is_csr && alu_op[1:0] == 2'b11;

    ///////// Register file /////////

    wire [3:0] data_rs1;
    wire [3:0] data_rs2;
    reg [3:0] data_rd;
    reg wr_en;

    reg [31:0] tmp_data;

    tinyqv_registers #(.REG_ADDR_BITS(REG_ADDR_BITS), .NUM_REGS(NUM_REGS)) 
        i_registers(clk, rstn, wr_en, counter, rs1, rs2, rd, data_rs1, data_rs2, data_rd, return_addr);


    ///////// ALU /////////

    wire is_slt = alu_op[3:1] == 3'b001;

    reg [0:0] alu_cycles;
    always @(*) begin
        if (is_slt || is_shift || is_mul) alu_cycles = 1;
        else alu_cycles = 0;
    end

    reg cy;
    reg cmp;
    wire [3:0] alu_op_in = is_czero ? 4'b0100 : alu_op;
    wire [3:0] alu_a_in = is_czero ? 4'b0000 : 
                          (is_auipc || is_jal) ? pc : data_rs1;
    wire [3:0] alu_b_in = (is_alu_reg || is_branch) ? data_rs2 : imm;
    wire [3:0] alu_out;
    wire cy_in = (counter == 0) ? (alu_op_in[1] || alu_op_in[3]) : cy;
    wire cmp_in = (counter == 0) ? 1'b1 : cmp;
    wire cy_out, cmp_out;

    tinyqv_alu i_alu(alu_op_in, alu_a_in, alu_b_in, cy_in, cmp_in, alu_out, cy_out, cmp_out);

    always @(posedge clk) begin
        cy <= cy_out;
        cmp <= cmp_out;
    end

    ///////// Shifter /////////

    reg [4:0] shift_amt;
    always @(posedge clk) begin
        if (cycle == 0) begin
            if (counter == 0) shift_amt[3:0] <= is_alu_imm ? imm : data_rs2;
            else if (counter == 1) shift_amt[4] <= is_alu_imm ? imm[0] : data_rs2[0];
        end
    end

    wire [3:0] shift_out;
    tinyqv_shifter i_shift(alu_op[3:2], counter, tmp_data, shift_amt, shift_out);


    ///////// Multiplier /////////

    wire [3:0] mul_out;
    tinyqv_mul #(.B_BITS(16)) multiplier(clk, data_rs1 & {4{cycle[0]}}, tmp_data[15:0], mul_out);


    ///////// Writeback /////////

    reg load_top_bit_next;
    reg load_top_bit;
    always @(*) begin
        load_top_bit_next = (counter == 0) ? 0 : load_top_bit;
        if (is_load && load_data_ready &&
            ((mem_op == 3'b001 && counter == 3) || 
             (mem_op == 3'b000 && counter == 1)))
        begin
            load_top_bit_next = data_in[3];
        end
    end

    always @(posedge clk)
        load_top_bit <= load_top_bit_next;

    always @(*) begin
        wr_en = 0;
        data_rd = 0;
        if (is_alu_imm || is_alu_reg || is_auipc) begin
            wr_en = 1;
            if (is_czero) begin
                if (cycle == 1) data_rd = tmp_data[3:0];
            end else if (is_slt && cycle == 1 && counter == 0)
                data_rd = {3'b000, cmp};
            else if (is_shift && cycle == 1)
                data_rd = shift_out;
            else if (is_mul) begin
                wr_en = cycle[0];
                data_rd = mul_out;
            end else
                data_rd = alu_out;

        end else if (is_load && load_data_ready) begin
            wr_en = 1;
            if ((mem_op[1:0] == 2'b00 && counter > 1) ||
                (mem_op[1:0] == 2'b01 && counter > 3))
                data_rd = {4{load_top_bit}};
            else
                data_rd = data_in;

        end else if (is_lui) begin
            wr_en = 1;
            data_rd = imm;
        end else if (is_jal || is_jalr) begin
            wr_en = 1;
            data_rd = next_pc;
        end else if (is_csr) begin
            // CSR read
            wr_en = 1;
            data_rd = csr_read;
        end
    end


    ///////// Branching /////////

    wire take_branch = last_count && (cmp_out ^ mem_op[0]);
    assign branch = last_count && ((is_jal || is_jalr || is_trap || is_interrupt || is_mret) || (is_branch && take_branch));


    ///////// Cycle management /////////

    always @(posedge clk) begin
        if (!rstn) cycle <= 0;
        else if (last_count) begin
            if (instr_complete) cycle <= 0;
            else if (cycle != 2'b11) cycle <= cycle + 1;
        end
    end

    reg load_done;
    always @(*) begin
        instr_complete = 0;
        if (last_count) begin
            if (is_auipc || is_lui || is_store || is_jal || is_jalr || is_system || is_stall || is_exception || is_branch)
                instr_complete = 1;
            else if (is_czero)
                instr_complete = cycle[0] || (cmp_out ^ alu_op[0]);
            else if (is_alu_imm || is_alu_reg)
                instr_complete = cycle[0:0] == alu_cycles;
            else if (load_done && is_load)
                instr_complete = 1;
        end
    end

    always @(posedge clk) begin
        if (counter == 0)
            load_done <= load_data_ready && cycle[1] != 1'b0;
    end

    assign address_ready = last_count && (cycle == 0) && (is_load || is_store);


    ///////// Working temporary data /////////

    reg [3:0] tmp_data_in;
    reg tmp_data_shift;
    
    always @(*) begin
        tmp_data_shift = 1;
        if (is_exception)
            tmp_data_in = (counter == 0) ? {is_interrupt, is_trap && mstatus_mte, 2'b00} : 4'b0000;
        else if (is_shift || is_czero)
            tmp_data_in = data_rs1;
        else if (is_mul)
            tmp_data_in = data_rs2;
        else if (cycle == 0)
            tmp_data_in = alu_out;
        else
            tmp_data_in = data_rs2;
        
        if (cycle == 1 && (is_shift || is_mul))
            tmp_data_shift = 0;
    end

    always @(posedge clk) begin
        if (tmp_data_shift)
            tmp_data <= {tmp_data_in, tmp_data[31:4]};
    end

    assign addr_out = is_mret ? {4'b0000, mepc} : tmp_data[31:4];

    always @(*) begin
        data_out = data_rs2;
        if ((mem_op[1:0] == 2'b00 && counter > 1) ||
            (mem_op[1:0] == 2'b01 && counter > 3))
            data_out = 0;
    end


    ///////// Counters /////////

    wire [6:0] cycle_count_wide;
    wire cycle_cy;
    tinyqv_counter #(.OUTPUT_WIDTH(7)) i_cycles (
        .clk(clk),
        .rstn(rstn),
        .add(1'b1),
        .counter(counter),
        .data(cycle_count_wide),
        .cy_out(cycle_cy)
    );

    reg [2:0] time_hi;
    always @(posedge clk) begin
        if (!rstn) time_hi <= 0;
        else if (counter == 7 && cycle_cy) time_hi <= time_hi + 3'b001;
    end

    wire [3:0] cycle_count = cycle_count_wide[3:0];
    wire [3:0] time_count = (counter == 7) ? {time_hi, cycle_count_wide[3]} : cycle_count_wide[6:3];

    wire [3:0] instrret_count;
    reg instr_retired;
    always @(posedge clk) begin
        instr_retired <= instr_complete && !is_stall;
    end
    /* verilator lint_off PINMISSING */  // No carry
    tinyqv_counter i_instrret (
        .clk(clk),
        .rstn(rstn),
        .add(instr_retired),
        .counter(counter),
        .data(instrret_count)
    );
    /* verilator lint_on PINMISSING */


    ///////// Traps and interrupts /////////    

    reg [17:16] mip_reg;
    wire [19:16] mip = {interrupt_req[3:2], mip_reg};
    reg [19:16] mie;

    reg [5:0] mcause;
    always @(posedge clk) begin
        if (!rstn) mcause <= 0;
        else if (counter == 0) begin
            if (is_interrupt) begin
                mcause[5:2] <= 4'b1100;
                casez (mip & mie)
                    4'b???1: mcause[1:0] <= 2'b00;
                    4'b??10: mcause[1:0] <= 2'b01;
                    4'b?100: mcause[1:0] <= 2'b10;
                    4'b1000: mcause[1:0] <= 2'b11;
                    default: mcause[1:0] <= 2'b00;  // Shouldn't be possible
                endcase
            end else if (is_trap) begin
                if (imm == 4'b0000)      mcause <= 6'd11;  // ECALL
                else if (imm == 4'b0001) mcause <= 6'd3;   // EBREAK
                else                     mcause <= 6'd2;   // Illegal instruction
            end
        end
    end

    // mstatus_mte is cleared while handling a trap, so need to latch double fault on counter==0.
    reg is_double_fault_r;
    always @(posedge clk) begin
        if (counter == 0)
            is_double_fault_r <= is_trap && !mstatus_mte;
    end
    wire is_double_fault = (counter == 0 && is_trap && !mstatus_mte) || is_double_fault_r;

    always @(posedge clk) begin
        if (counter <= 5) begin
            mepc[23:20] <= (!rstn)                             ? 4'b0000 :
                           (is_exception)                      ? pc : 
                           (is_csr_write && imm_lo == 12'h341) ? data_rs1 :
                                                                 mepc[3:0];
            mepc[19:0] <= mepc[23:4];
        end
    end

    always @(posedge clk) begin
        if (!rstn || is_double_fault) begin
            mstatus_mte <= 1;
            mstatus_mie <= 1;
            mstatus_mpie <= 0;
        end else if (counter == 0 && (is_exception)) begin
            mstatus_mpie <= mstatus_mie;
            mstatus_mie <= 0;
            mstatus_mte <= 0;
        end else if (is_mret) begin
            mstatus_mie <= mstatus_mpie;
            mstatus_mte <= 1;
        end else if (imm_lo == 12'h300) begin
            if (counter == 0) begin
                if (is_csr_write) mstatus_mie <= data_rs1[3];
                else if (is_csr_set && data_rs1[3]) mstatus_mie <= 1;
                else if (is_csr_clear && data_rs1[3]) mstatus_mie <= 0;
            end else if (counter == 1) begin
                if (is_csr_write) mstatus_mpie <= data_rs1[3];
                else if (is_csr_set && data_rs1[3]) mstatus_mpie <= 1;
                else if (is_csr_clear && data_rs1[3]) mstatus_mpie <= 0;
            end
        end
    end

    // Interrupts 1 and 0 trigger on rising edge
    reg [1:0] last_interrupt_req;

    always @(posedge clk) begin
        if (!rstn || is_double_fault) begin
            mie <= 0;
            mip_reg <= 0;
        end else if (counter == 4) begin
            if (imm_lo == 12'h304) begin
                if (is_csr_write) mie <= data_rs1;
                else if (is_csr_set) mie <= mie | data_rs1;
                else if (is_csr_clear) mie <= mie & ~data_rs1;
            end else if (imm_lo == 12'h344) begin 
                if (is_csr_write) mip_reg <= data_rs1[1:0];
                else if (is_csr_set) mip_reg <= mip_reg | data_rs1[1:0];
                else if (is_csr_clear) mip_reg <= mip_reg & ~data_rs1[1:0];
            end
        end else if (counter == 5) begin
            last_interrupt_req <= interrupt_req[1:0];
            mip_reg <= mip_reg | (interrupt_req[1:0] & ~last_interrupt_req);
        end
    end

    assign interrupt_pending = mstatus_mie && |(mip & mie);


    ///////// CSRs /////////    

    always @(*) begin
        case (imm_lo) 
            // mstatus
            12'h300: csr_read = (counter == 0) ? {mstatus_mie, mstatus_mte, 2'b00} :
                                (counter == 1) ? {mstatus_mpie, 3'b000} :
                                                 4'b0000;

            // misa
            12'h301: csr_read = (counter == 0 || counter == 7) ? 4'b0100 :  // C, 32
                                (counter == 1) ?                 4'b0001 :  // E
                                                                 4'b0000;
            
            // mie
            12'h304: csr_read = (counter == 4) ? mie : 4'b0000;

            // mepc
            12'h341: csr_read = (counter <= 5) ? mepc[3:0] : 4'b0000;

            // mcause
            12'h342: csr_read = (counter == 0) ? mcause[3:0] :
                                (counter == 1) ? {3'b000, mcause[4]} :
                                (counter == 7) ? {mcause[5], 3'b000} :
                                                 4'b0000;
            
            // mip
            12'h344: csr_read = (counter == 4) ? mip : 4'b0000;

            12'hC00: csr_read = cycle_count;
            12'hC01: csr_read = time_count;
            12'hC02: csr_read = instrret_count;
            default: csr_read = 4'b0000;
        endcase
    end


    ////////// Debug //////////
    assign debug_reg_wen = wr_en;
    assign debug_rd = data_rd;

endmodule
