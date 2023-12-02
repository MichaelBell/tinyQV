/* Tiny45: A RISC-V core designed to use minimal area.
  
   This core module takes decoded instructions and produces output data
 */

module tiny45_cpu #(parameter NUM_REGS=16, parameter REG_ADDR_BITS=4) (
    input clk,
    input rstn,

    output [23:1] instr_addr,
    output        instr_fetch_restart,
    output        instr_fetch_stall,

    input         instr_fetch_started,
    input         instr_fetch_stopped,
    input  [15:0] instr_data_in,
    input         instr_ready,

    output reg [27:0] data_addr,
    output reg [1:0]  data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    output reg [1:0]  data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    output reg [31:0] data_out,

    input         data_ready,  // Transaction complete/data request can be modified.
    input  [31:0] data_in
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
    wire is_system_de;

    wire [2:1] instr_len_de;
    wire [3:0] alu_op_de;
    wire [2:0] mem_op_de;

    wire [3:0] rs1_de;
    wire [3:0] rs2_de;
    wire [3:0] rd_de;

    tiny45_decoder i_decoder(
        instr, 
        imm_de,

        is_load_de,
        is_alu_imm_de,
        is_auipc_de,
        is_store_de,
        is_alu_reg_de,
        is_lui_de,
        is_branch_de,
        is_jalr_de,
        is_jal_de,
        is_system_de,

        instr_len_de,
        alu_op_de,  // See tiny45_alu for format
        mem_op_de,

        rs1_de,
        rs2_de,
        rd_de);

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

    reg instr_valid;

    wire [31:0] pc;

    wire [27:0] addr_out;
    wire address_ready;
    wire instr_complete;
    wire branch;

    reg [4:2] counter_hi;
    wire [4:0] counter = {counter_hi, 2'b00};

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
            instr_len <= 2'b10;
        end else if (instr_complete) begin
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
            instr_valid <= ({1'b0,instr_len_de} <= instr_avail_len);
        end
    end

    wire [3:0] data_out_slice;
    always @(posedge clk) begin
        if (!rstn) begin
            counter_hi <= 0;
        end else begin
            counter_hi <= counter_hi + 1;
        end

        if (address_ready) begin
            data_addr <= addr_out;
        end

        if (is_store) begin
            data_out[counter+:4] <= data_out_slice;
        end

        data_write_n <= (is_store && address_ready) ? mem_op[1:0] : 2'b11; 
        data_read_n  <= (is_load && address_ready)  ? mem_op[1:0] : 2'b11;
    end

    tiny45_core #(.REG_ADDR_BITS(REG_ADDR_BITS), .NUM_REGS(NUM_REGS))  i_core(
        clk,
        rstn,
        
        imm[counter+:4],

        is_load && instr_valid,
        is_alu_imm && instr_valid,
        is_auipc && instr_valid,
        is_store && instr_valid,
        is_alu_reg && instr_valid,
        is_lui && instr_valid,
        is_branch && instr_valid,
        is_jalr && instr_valid,
        is_jal && instr_valid,
        is_system && instr_valid,
        !instr_valid,

        alu_op,
        mem_op,

        rs1,
        rs2,
        rd,

        counter[4:2],
        pc[counter+:4],
        data_in[counter+:4],
        data_ready,

        data_out_slice,
        addr_out,
        address_ready,
        instr_complete,
        branch
        );

    /////// Instruction fetch ///////

    reg [15:0] instr_data[0:3];

    reg [23:3] instr_data_start;

    reg [2:1] pc_offset;
    reg [3:1] instr_write_offset;

    reg instr_fetch_running;

    wire [3:1] next_pc_offset = {1'b0, pc_offset} + {1'b0, instr_len};
    wire pc_wrap = next_pc_offset[3] && instr_complete && instr_valid;
    wire [3:1] instr_avail_len = instr_write_offset - (instr_valid ? next_pc_offset : {1'b0, pc_offset});

    wire [3:1] next_instr_write_offset = instr_write_offset + (instr_ready ? 3'b001 : 3'b000) - (pc_wrap ? 3'b100 : 3'b000);
    wire next_instr_stall = (next_instr_write_offset == {1'b1, pc_offset});

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
                instr_data_start <= addr_out[23:3];
                instr_write_offset <= {1'b0, addr_out[2:1]};
                pc_offset <= addr_out[2:1];
                instr_fetch_running <= 0;
            end
            else begin
                if (instr_fetch_started)      instr_fetch_running <= 1;
                else if (instr_fetch_stopped) instr_fetch_running <= 0;

                instr_write_offset <= next_instr_write_offset;

                if (instr_complete && instr_valid) begin
                    pc_offset <= next_pc_offset[2:1];
                    if (next_pc_offset[3]) begin
                        instr_data_start <= instr_data_start + 21'd1;
                    end
                end
                if (instr_ready && instr_fetch_running) begin
                    instr_data[instr_write_offset[2:1]] <= instr_data_in;
                end
            end
        end
    end

    assign instr_fetch_restart = branch || !instr_fetch_running;
    assign instr_fetch_stall = next_instr_stall;

    assign instr_addr = {instr_data_start, 2'b00} + {20'd0, instr_write_offset};

    assign instr = instr_valid ? {instr_data[next_pc_offset[2:1] + 2'b01], instr_data[next_pc_offset[2:1]]} : {instr_data[pc_offset + 2'b01], instr_data[pc_offset]};
    assign pc = {8'h00, instr_data_start, pc_offset, 1'b0};

endmodule
