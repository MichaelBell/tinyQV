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
    output reg        data_write,
    output reg        data_read,
    output reg [31:0] data_out,

    input         data_ready,  // Transaction complete/data request can be modified.
    input  [31:0] data_in
);

    wire [31:0] instr;

    // Potentially register this
    wire [31:0] imm;

    wire is_load;
    wire is_alu_imm;
    wire is_auipc;
    wire is_store;
    wire is_alu_reg;
    wire is_lui;
    wire is_branch;
    wire is_jalr;
    wire is_jal;
    wire is_system;

    wire [2:1] instr_len;
    wire [3:0] alu_op;
    wire [2:0] mem_op;

    wire [3:0] rs1;
    wire [3:0] rs2;
    wire [3:0] rd;

    wire [31:0] pc;

    wire [27:0] addr_out;
    wire address_ready;
    wire instr_complete;
    wire branch;

    tiny45_decoder i_decoder(
        instr, 
        imm,

        is_load,
        is_alu_imm,
        is_auipc,
        is_store,
        is_alu_reg,
        is_lui,
        is_branch,
        is_jalr,
        is_jal,
        is_system,

        instr_len,
        alu_op,  // See tiny45_alu for format
        mem_op,

        rs1,
        rs2,
        rd);

    reg [4:2] counter_hi;
    wire [4:0] counter = {counter_hi, 2'b00};

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

        data_write <= (is_store && address_ready); 
        data_read <= (is_load && address_ready);
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
    wire pc_wrap = next_pc_offset[3] && !branch && instr_complete;
    wire [3:1] instr_avail_len = instr_write_offset - {1'b0, pc_offset};
    wire instr_valid = ({1'b0,instr_len} <= instr_avail_len);

    wire [3:1] next_instr_write_offset = instr_write_offset + (instr_ready ? 3'b001 : 3'b000) - (pc_wrap ? 3'b100 : 3'b000);
    wire next_instr_stall = (next_instr_write_offset == {1'b1, pc_offset});

    always @(posedge clk) begin
        if (!rstn) begin
            instr_data_start <= 0;
            pc_offset <= 0;
            instr_write_offset <= 0;
            instr_fetch_running <= 0;

        end else begin
            if (instr_fetch_started)      instr_fetch_running <= 1;
            else if (instr_fetch_stopped) instr_fetch_running <= 0;

            if (branch) begin
                instr_data_start <= addr_out[23:3];
                instr_write_offset <= {1'b0, addr_out[2:1]};
                pc_offset <= addr_out[2:1];
                instr_fetch_running <= 0;
            end
            else begin
                if (instr_complete) begin
                    pc_offset <= next_pc_offset[2:1];
                    if (next_pc_offset[3]) begin
                        instr_data_start <= instr_data_start + 21'd1;
                    end
                end
                if (instr_ready && instr_fetch_running) begin
                    instr_data[instr_write_offset[2:1]] <= instr_data_in;
                    instr_write_offset <= next_instr_write_offset;
                end
            end
        end
    end

    assign instr_fetch_restart = branch || !instr_fetch_running;
    assign instr_fetch_stall = next_instr_stall;

    assign instr_addr = {instr_data_start, 2'b00} + {20'd0, instr_write_offset};

    assign instr = {instr_data[pc_offset + 2'b01], instr_data[pc_offset]};
    assign pc = {8'h00, instr_data_start, pc_offset, 1'b0};

endmodule
