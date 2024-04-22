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
    input   [7:0] instr_data_in,
    input         instr_ready,

    output reg [27:0] data_addr,
    output reg [1:0]  data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    output reg [1:0]  data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    output reg [31:0] data_out,

    input   [3:0] data_ready,  // Byte strobe for data ready.  If data available a byte at a 
                               // time the bytes must go from low to high.
                               // Transaction complete/data request can be modified, once the
                               // top requested bit is set.
                               // Writes must complete together - only the bottom bit is checked.
    input  [31:0] data_in
);

    // Decoder interface
    reg [31:0] instr;

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

    wire [2:0] instr_len;
    wire [3:0] alu_op;
    wire [2:0] mem_op;

    wire [REG_ADDR_BITS-1:0] rs1;
    wire [REG_ADDR_BITS-1:0] rs2;
    wire [REG_ADDR_BITS-1:0] rd;

    tinyqv_decoder #(.REG_ADDR_BITS(REG_ADDR_BITS)) i_decoder(
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
        alu_op,  // See tinyqv_alu for format
        mem_op,

        rs1,
        rs2,
        rd);

    reg instr_valid;

    reg  [23:1] pc_reg;
    wire [23:0] pc = {pc_reg, 1'b0};

    wire [31:0] data_out_core;
    wire [27:0] addr_out;
    wire address_ready;
    wire instr_complete_core;
    wire branch;

    reg no_write_in_progress;
    reg load_started;
    wire stall_core = !instr_valid || ((is_store || is_load) && !no_write_in_progress);
    wire instr_complete = instr_complete_core && !stall_core;

    reg [2:0] instr_avail_len;

    always @(posedge clk) begin
        if (!rstn) begin
            instr_valid <= 0;
        end else if (branch) begin
            instr_valid <= 0;
        end else if (!instr_valid) begin
            if (instr_len <= instr_avail_len) begin
                instr_valid <= !branch;
            end else begin
                instr_valid <= 0;
            end
        end else if (instr_complete) instr_valid <= 0;
    end

    always @(posedge clk) begin
        if (!rstn) begin
            // Only need to reset the pins that determine how
            // the address is routed
            data_addr[27:24] <= 4'b000;
        end else if (address_ready) begin
            data_addr <= addr_out;
        end
    end

    reg read_complete;
    always @(*) begin
        read_complete = 0;
        if (data_read_n == 2'b00 && data_ready[0]) read_complete = 1;
        if (data_read_n == 2'b01 && data_ready[1]) read_complete = 1;
        if (data_read_n == 2'b10 && data_ready[3]) read_complete = 1;
    end

    always @(posedge clk) begin
        if (!rstn) begin
            data_write_n <= 2'b11;
            no_write_in_progress <= 1;
        end else if (is_store && address_ready) begin
            data_write_n <= mem_op[1:0];
            no_write_in_progress <= 0;
        end else if (data_ready[0]) begin
            data_write_n <= 2'b11;
            no_write_in_progress <= 1;
        end else begin
            no_write_in_progress <= data_write_n == 2'b11;
        end
        
        if (is_load && !instr_complete) begin
            if (address_ready) begin
                data_read_n <= mem_op[1:0]; 
                load_started <= 1;
            end 
            if (read_complete && load_started) begin
                data_read_n <= 2'b11;
            end 
        end else begin
            data_read_n <= 2'b11;
            load_started <= 0;
        end
    end

    always @(posedge clk) begin
        if (is_store && no_write_in_progress) begin
            data_out <= data_out_core;
        end
    end

    wire [23:0] next_pc = pc + {21'd0, instr_len};

    tinyqv_core #(.REG_ADDR_BITS(REG_ADDR_BITS), .NUM_REGS(NUM_REGS))  i_core(
        clk,
        rstn,
        
        imm,

        is_load && instr_valid && no_write_in_progress,
        is_alu_imm && instr_valid,
        is_auipc && instr_valid,
        is_store && instr_valid && no_write_in_progress,
        is_alu_reg && instr_valid,
        is_lui && instr_valid,
        is_branch && instr_valid,
        is_jalr && instr_valid,
        is_jal && instr_valid,
        is_system && instr_valid,
        stall_core,

        alu_op,
        mem_op,

        rs1,
        rs2,
        rd,

        pc,
        next_pc,
        data_in,
        data_ready,

        data_out_core,
        addr_out,
        address_ready,
        instr_complete_core,
        branch
        );

    /////// Instruction fetch ///////

    reg instr_fetch_running;

    always @(posedge clk) begin
        if (!rstn) begin
            pc_reg <= 0;
            instr_avail_len <= 0;
            instr_fetch_running <= 0;

        end else begin

            if (branch) begin
                pc_reg <= addr_out[23:1];
                instr_avail_len <= 0;
                instr_fetch_running <= 0;
            end
            else begin
                if (instr_fetch_started) instr_fetch_running <= 1;
                else if (instr_fetch_stopped) instr_fetch_running <= 0;

                if (instr_complete) begin
                    instr_avail_len <= instr_avail_len - instr_len;
                    instr <= {16'b0, instr[31:16]};
                    pc_reg <= next_pc[23:1];
                end
                if (instr_ready && instr_fetch_running) begin
                    instr[instr_avail_len * 8 +:8] <= instr_data_in;
                    instr_avail_len <= instr_avail_len + 3'b001;
                end
            end
        end
    end

    // Make sure instr_fetch_restart pulses low on branch
    assign instr_fetch_restart = !instr_fetch_running && !branch;
    assign instr_fetch_stall = instr_avail_len[2];

    assign instr_addr = pc_reg + {21'b0, instr_avail_len[2:1]};

endmodule
