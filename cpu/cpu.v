/* TinyQV: A RISC-V core designed to use minimal area.
  
   This CPU module interfaces with memory, the instruction decoder and the core.
 */

module tinyqv_cpu #(parameter NUM_REGS=16, parameter REG_ADDR_BITS=4) (
    input clk,
    input rstn,

    output [23:1] instr_addr,
    output        instr_fetch_restart,
    output        instr_fetch_stall,

    input         instr_fetch_started,
    input         instr_fetch_stopped,
    input  [15:0] instr_data_in,
    input         instr_ready,

    input  [15:0] interrupt_req,

    output reg [27:0] data_addr,
    output reg [1:0]  data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    output reg [1:0]  data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    output            data_read_complete,
    output reg [31:0] data_out,

    output reg    data_continue,

    input         data_ready,  // Transaction complete/data request can be modified.
    input  [31:0] data_in,

    input         time_pulse,  // High for one clock once per microsecond.

    output        debug_instr_complete,
    output        debug_instr_valid,
    output        debug_interrupt_pending,
    output        debug_branch,
    output        debug_early_branch,
    output        debug_ret,
    output        debug_reg_wen,
    output        debug_counter_0,
    output [3:0] debug_rd
);

    // Decoder interface
    // _de suffix used for decoded instruction that will be registered
    wire [31:0] instr;

    wire [31:0] imm_de;

    wire is_load_de;
    wire is_alu_imm_de;
    wire is_auipc_de;
    wire is_store_de;
    wire is_alu_reg_de;
    wire is_lui_de;
    wire is_branch_de;
    wire is_jalr_de;
    wire is_jal_de;
    wire is_ret_de;
    wire is_system_de;

    wire [2:1] instr_len_de;
    wire [3:0] alu_op_de;
    wire [2:0] mem_op_de;

    wire [3:0] rs1_de;
    wire [3:0] rs2_de;
    wire [3:0] rd_de;
    wire [2:0] additional_mem_ops_de;
    wire mem_op_increment_reg_de;

    tinyqv_decoder i_decoder(
        .instr(instr),
        .imm(imm_de),

        .is_load(is_load_de),
        .is_alu_imm(is_alu_imm_de),
        .is_auipc(is_auipc_de),
        .is_store(is_store_de),
        .is_alu_reg(is_alu_reg_de),
        .is_lui(is_lui_de),
        .is_branch(is_branch_de),
        .is_jalr(is_jalr_de),
        .is_jal(is_jal_de),
        .is_ret(is_ret_de),
        .is_system(is_system_de),

        .instr_len(instr_len_de),
        .alu_op(alu_op_de),  // See tinyqv_alu for format
        .mem_op(mem_op_de),

        .rs1(rs1_de),
        .rs2(rs2_de),
        .rd(rd_de),
        .additional_mem_ops(additional_mem_ops_de),
        .mem_op_increment_reg(mem_op_increment_reg_de)
    );

    reg [31:0] imm;

    reg is_load;
    reg is_alu_imm;
    reg is_auipc;
    reg is_store;
    reg is_alu_reg;
    reg is_lui;
    reg is_branch;
    reg is_jalr;
    reg is_jal;
    reg is_system;

    reg [2:1] instr_len;
    reg [3:0] alu_op;
    reg [2:0] mem_op;

    reg [3:0] rs1;
    reg [3:0] rs2;
    reg [3:0] rd;
    reg [2:0] additional_mem_ops;
    reg [3:2] addr_offset;
    reg mem_op_increment_reg;

    reg interrupt_core;

    reg instr_valid;

    wire [31:0] pc;
    wire [31:0] next_pc_for_core;

    wire [27:0] addr_out;
    wire address_ready;
    wire instr_complete_core;
    wire branch;
    wire [23:1] return_addr;
    wire interrupt_pending;
    wire any_additional_mem_ops = additional_mem_ops != 3'b000;

    reg [4:2] counter_hi;
    wire [4:0] counter = {counter_hi, 2'b00};

    wire timer_interrupt;
    wire [3:0] timer_data;
    wire is_timer_addr;

    reg no_write_in_progress;
    reg load_started;
    wire stall_core = !instr_valid || ((is_store || is_load) && !no_write_in_progress);
    wire instr_complete = instr_complete_core && !stall_core && !any_additional_mem_ops;

    reg [2:1] pc_offset;
    reg [3:1] instr_write_offset;
    reg was_early_branch;

    wire [3:1] next_pc_offset = {1'b0, pc_offset} + {1'b0, instr_len};
    wire [3:1] instr_avail_len = was_early_branch ? 3'b000 :
                                                    instr_write_offset - (instr_valid ? next_pc_offset : {1'b0, pc_offset});

    always @(posedge clk) begin
        if (!rstn) begin
            instr_valid <= 0;
            is_load <= 0;
            is_alu_imm <= 0;
            is_auipc <= 0;
            is_store <= 0;
            is_alu_reg <= 0;
            is_lui <= 0;
            is_branch <= 0;
            is_jalr <= 0;
            is_jal <= 0;
            is_system <= 0;
            alu_op <= 0;
            imm[9:8] <= 0;  // These particular bits need to be reset as the core relies on them being initialized.
            instr_len <= 2'b10;
            additional_mem_ops <= 3'b000;
            addr_offset <= 2'b00;
            interrupt_core <= 0;
        end else if (any_additional_mem_ops && instr_complete_core && !stall_core) begin
            rs2 <= rs2 + {3'b000, mem_op_increment_reg};
            rd <= rd + 4'b0001;
            additional_mem_ops <= additional_mem_ops - 3'b001;
            addr_offset <= addr_offset + 2'b01;
        end else if (instr_complete_core && !any_additional_mem_ops && no_write_in_progress && interrupt_pending) begin
            instr_valid <= 0;
            interrupt_core <= 1;
        end else if ((counter_hi == 3'd7 && !instr_valid) || instr_complete || branch) begin
            interrupt_core <= 0;
            if ({1'b0,instr_len_de} <= instr_avail_len) begin
                imm <= imm_de;
                is_load <= is_load_de;
                is_alu_imm <= is_alu_imm_de;
                is_auipc <= is_auipc_de;
                is_store <= is_store_de;
                is_alu_reg <= is_alu_reg_de;
                is_lui <= is_lui_de;
                is_branch <= is_branch_de;
                is_jalr <= is_jalr_de;
                is_jal <= is_jal_de;
                is_system <= is_system_de;
                instr_len <= instr_len_de;
                alu_op <= alu_op_de;
                mem_op <= mem_op_de;
                rs1 <= rs1_de;
                rs2 <= rs2_de;
                rd <= rd_de;
                additional_mem_ops <= additional_mem_ops_de;
                addr_offset <= 2'b00;
                mem_op_increment_reg <= mem_op_increment_reg_de;
                instr_valid <= !branch && !is_ret_de;
            end else begin
                instr_valid <= 0;
            end
        end
    end

    reg early_branch;
    reg is_ret;
    always @(*) begin
        early_branch = 0;
        is_ret = 0;
        if (!rstn) begin
        end else if (any_additional_mem_ops && instr_complete_core && !stall_core) begin
        end else if (instr_complete_core && interrupt_pending) begin
        end else if (((counter_hi == 3'd7 && !instr_valid) || instr_complete) && {1'b0,instr_len_de} <= instr_avail_len) begin
            early_branch = is_jal_de && !branch;
            is_ret = is_ret_de && !branch;
        end
    end

    wire [3:0] data_out_slice;
    wire data_ready_ext = data_ready && data_addr[27:26] != 2'b11;
    reg data_ready_latch;
    reg data_ready_sync;
    wire data_ready_core;
    always @(posedge clk) begin
        if (!rstn) begin
            counter_hi <= 0;
            data_ready_sync <= 0;
            data_ready_latch <= 0;
        end else begin
            counter_hi <= counter_hi + 1;

            if (counter_hi == 3'd0) begin
                data_ready_latch <= 0;
                if (data_ready_ext || data_ready_latch || is_timer_addr) begin
                    data_ready_sync <= 1;
                end else begin
                    data_ready_sync <= 0;
                end
            end else if (!data_ready_latch) begin
                data_ready_latch <= data_ready_ext;
            end else if (address_ready) begin
                data_ready_latch <= 0;
            end
        end
    end

    assign data_ready_core = (counter_hi == 3'd0) ? (data_ready_ext || data_ready_latch || is_timer_addr) : data_ready_sync;

    always @(posedge clk) begin
        if (!rstn) begin
            data_addr <= 0;
        end else if (address_ready) begin
            // Cycle address within 16-byte window for additional mem op instructions.
            // Note this only matters for peripherals - the memory controller ignores the address for data_continue.
            data_addr <= {addr_out[27:4], addr_out[3:2] + addr_offset, addr_out[1:0]};
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            data_write_n <= 2'b11;
            no_write_in_progress <= 1;
            data_continue <= 0;
        end else if (is_store && address_ready) begin
            data_write_n <= mem_op[1:0];
            no_write_in_progress <= addr_out[27];     // Assume that all writes to peripherals (high addr bit) complete immediately.
            data_continue <= any_additional_mem_ops;
        end else if (data_ready_ext) begin
            data_write_n <= 2'b11;
            if (counter_hi == 3'b111) no_write_in_progress <= 1;
        end else if (counter_hi == 3'b111) begin
            if (data_ready_sync) begin
                data_write_n <= 2'b11;
                no_write_in_progress <= 1;
            end else begin    
                no_write_in_progress <= data_write_n == 2'b11;
            end
        end
        
        if (is_load && !instr_complete) begin
            if (address_ready) begin
                data_read_n <= mem_op[1:0]; 
                load_started <= 1;
                data_continue <= any_additional_mem_ops;
            end 
            if (data_ready_ext && load_started) begin
                data_read_n <= 2'b11;
            end 
        end else begin
            data_read_n <= 2'b11;
            load_started <= 0;
        end
    end
    assign data_read_complete = is_load && instr_complete_core && !stall_core;

    always @(posedge clk) begin
        if (!rstn) begin
            data_out <= 0;
        end else if (is_store && no_write_in_progress) begin
            data_out[counter+:4] <= data_out_slice;
        end
    end

    always @(posedge clk) begin
        if (!rstn)
            was_early_branch <= 0;
        else if (counter_hi == 3'd7)
            was_early_branch <= early_branch && !branch;
    end

    tinyqv_core #(.REG_ADDR_BITS(REG_ADDR_BITS), .NUM_REGS(NUM_REGS))  i_core(
        .clk(clk),
        .rstn(rstn),
        
        .imm(imm[counter+:4]),
        .imm_lo(imm[11:0]),

        .is_load(is_load && instr_valid && no_write_in_progress),
        .is_alu_imm(is_alu_imm && instr_valid),
        .is_auipc(is_auipc && instr_valid),
        .is_store(is_store && instr_valid && no_write_in_progress),
        .is_alu_reg(is_alu_reg && instr_valid),
        .is_lui(is_lui && instr_valid),
        .is_branch(is_branch && instr_valid),
        .is_jalr(is_jalr && instr_valid),
        .is_jal(is_jal && instr_valid),
        .is_system(is_system && instr_valid),
        .is_interrupt(interrupt_core),
        .is_stall(stall_core && !interrupt_core),

        .alu_op(alu_op),
        .mem_op(mem_op),

        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),

        .counter(counter[4:2]),
        .pc(pc[counter+:4]),
        .next_pc(next_pc_for_core[counter+:4]),
        .data_in(is_timer_addr ? timer_data : data_in[counter+:4]),
        .load_data_ready(data_ready_core),

        .data_out(data_out_slice),
        .addr_out(addr_out),
        .address_ready(address_ready),
        .instr_complete(instr_complete_core),
        .branch(branch),
        .return_addr(return_addr),

        .interrupt_req(interrupt_req),
        .timer_interrupt(timer_interrupt),
        .interrupt_pending(interrupt_pending),

        .debug_reg_wen(debug_reg_wen),
        .debug_rd(debug_rd)
    );

    /////// Instruction fetch ///////

    reg [15:0] instr_data[0:3];

    reg [23:3] instr_data_start;
    reg instr_fetch_running;

    wire [23:0] next_pc = {instr_data_start, 3'b000} + {20'd0, next_pc_offset, 1'b0};
    wire pc_wrap = next_pc_offset[3] && instr_complete;

    wire [3:1] next_instr_write_offset = instr_write_offset + (instr_ready && instr_fetch_running ? 3'b001 : 3'b000) - (pc_wrap ? 3'b100 : 3'b000);
    wire next_instr_stall = (next_instr_write_offset == {1'b1, pc_offset});

    wire [23:1] early_branch_addr = pc[23:1] + imm[23:1];

    always @(posedge clk) begin
        if (!rstn) begin
            instr_data[0][1:0] <= 2'b11;
            instr_data[1][1:0] <= 2'b11;
            instr_data[2][1:0] <= 2'b11;
            instr_data[3][1:0] <= 2'b11;
            instr_data_start <= 0;
            pc_offset <= 0;
            instr_write_offset <= 0;
            instr_fetch_running <= 0;

        end else begin

            if (branch) begin
                if (is_branch && instr_valid) begin
                    instr_data_start <= early_branch_addr[23:3];
                    instr_write_offset <= {1'b0, early_branch_addr[2:1]};
                    pc_offset <= early_branch_addr[2:1];
                end else begin
                    instr_data_start <= addr_out[23:3];
                    instr_write_offset <= {1'b0, addr_out[2:1]};
                    pc_offset <= addr_out[2:1];
                end
                instr_fetch_running <= was_early_branch;
            end
            else if (is_ret) begin
                instr_data_start <= return_addr[23:3];
                instr_write_offset <= {1'b0, return_addr[2:1]};
                pc_offset <= return_addr[2:1];
                instr_fetch_running <= 0;
            end
            else begin
                if (early_branch)             instr_fetch_running <= 0;
                else if (instr_fetch_started) instr_fetch_running <= 1;
                else if (instr_fetch_stopped) instr_fetch_running <= 0;

                instr_write_offset <= next_instr_write_offset;

                if (instr_complete) begin
                    pc_offset <= next_pc_offset[2:1];
                    instr_data_start <= next_pc[23:3];
                end
                if (instr_ready && instr_fetch_running) begin
                    instr_data[instr_write_offset[2:1]] <= instr_data_in;
                end
            end
        end
    end

    // Make sure instr_fetch_restart pulses low on branch
    assign instr_fetch_restart = !instr_fetch_running && (!branch || was_early_branch) && !early_branch && !is_ret;
    assign instr_fetch_stall = next_instr_stall;

    assign instr_addr = was_early_branch ? early_branch_addr : {instr_data_start, 2'b00} + {20'd0, instr_write_offset};

    wire [2:1] pc_offset_hi = pc_offset + 2'b01;
    wire [2:1] next_pc_offset_hi = next_pc_offset[2:1] + 2'b01;

    assign instr = instr_valid ? {instr_data[next_pc_offset_hi], instr_data[next_pc_offset[2:1]]} : {instr_data[pc_offset_hi], instr_data[pc_offset]};
    assign pc = {8'h00, instr_data_start, pc_offset, 1'b0};
    assign next_pc_for_core = {8'h00, next_pc};

    // Timer
    assign is_timer_addr = data_addr[27:4] == 24'hfffff0 && data_addr[3] == 0;
    wire is_timer_write = is_timer_addr && data_write_n != 2'b11;
    tinyQV_time i_timer (
        .clk(clk),
        .rstn(rstn),
        .time_pulse(time_pulse),
        .set_mtime(is_timer_write && !data_addr[2]),
        .set_mtimecmp(is_timer_write && data_addr[2]),
        .data_in(data_out_slice),
        .counter(counter_hi),
        .read_mtimecmp(data_addr[2]),
        .data_out(timer_data),
        .timer_interrupt(timer_interrupt)
    );

    // Debugging
    assign debug_instr_complete = instr_complete;
    assign debug_instr_valid = instr_valid;
    assign debug_interrupt_pending = interrupt_pending;
    assign debug_branch = branch;
    assign debug_early_branch = early_branch;
    assign debug_ret = is_ret;
    assign debug_counter_0 = (counter_hi == 3'b000);

endmodule
