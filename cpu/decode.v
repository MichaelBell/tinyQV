/* Decoder for tiny45.

    Note parts of this are from the excellent FemtoRV by Bruno Levy et al.
*/

module tiny45_decoder #(parameter REG_ADDR_BITS=4) (
    input [31:0] instr,

    output reg [31:0] imm,

    output is_load,
    output is_alu_imm,
    output is_auipc,
    output is_store,
    output is_alu_reg,
    output is_lui,
    output is_branch,
    output is_jalr,
    output is_jal,
    output is_system,

    output reg [3:0] alu_op,  // See tiny45_alu for format

    output [2:0] mem_op,      // Bit 0 of mem_op indicates branch condition is reversed

    output [REG_ADDR_BITS-1:0] rs1,
    output [REG_ADDR_BITS-1:0] rs2,
    output [REG_ADDR_BITS-1:0] rd
);

    wire [31:0] Uimm = {    instr[31],   instr[30:12], {12{1'b0}}};
    wire [31:0] Iimm = {{21{instr[31]}}, instr[30:20]};
    wire [31:0] Simm = {{21{instr[31]}}, instr[30:25],instr[11:7]};
    wire [31:0] Bimm = {{20{instr[31]}}, instr[7],instr[30:25],instr[11:8],1'b0};
    wire [31:0] Jimm = {{12{instr[31]}}, instr[19:12],instr[20],instr[30:21],1'b0};

    assign is_load    =  (instr[6:2] == 5'b00000); // rd <- mem[rs1+Iimm]
    assign is_alu_imm =  (instr[6:2] == 5'b00100); // rd <- rs1 OP Iimm
    assign is_auipc   =  (instr[6:2] == 5'b00101); // rd <- PC + Uimm
    assign is_store   =  (instr[6:2] == 5'b01000); // mem[rs1+Simm] <- rs2
    assign is_alu_reg =  (instr[6:2] == 5'b01100); // rd <- rs1 OP rs2
    assign is_lui     =  (instr[6:2] == 5'b01101); // rd <- Uimm
    assign is_branch  =  (instr[6:2] == 5'b11000); // if(rs1 OP rs2) PC<-PC+Bimm
    assign is_jalr    =  (instr[6:2] == 5'b11001); // rd <- PC+4; PC<-rs1+Iimm
    assign is_jal     =  (instr[6:2] == 5'b11011); // rd <- PC+4; PC<-PC+Jimm
    assign is_system  =  (instr[6:2] == 5'b11100); // rd <- csr - NYI

    // Determine immediate.  Hopefully muxing here is reasonable.
    always @(*) begin
        if (is_auipc || is_lui) imm = Uimm;
        else if (is_store) imm = Simm;
        else if (is_branch) imm = Bimm;
        else if (is_jal) imm = Jimm;
        else imm = Iimm;
    end

    // Determine alu op
    always @(*) begin
        if (is_load || is_auipc || is_store || is_jalr || is_jal) alu_op = 0;  // ADD
        else if (is_branch) alu_op = {1'b0, !instr[14], instr[14:13]};
        else alu_op = {instr[30] && (instr[5] || instr[13:12] == 2'b01),instr[14:12]};
    end

    assign mem_op = instr[14:12];

    assign rs1 = instr[15+:REG_ADDR_BITS];
    assign rs2 = instr[20+:REG_ADDR_BITS];
    assign rd  = instr[ 7+:REG_ADDR_BITS];

endmodule
