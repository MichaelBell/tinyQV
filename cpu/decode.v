/* Decoder for TinyQV.

    Note parts of this are from the excellent FemtoRV by Bruno Levy et al.
*/

module tinyqv_decoder #(parameter REG_ADDR_BITS=4) (
    input [31:0] instr,

    output reg [31:0] imm,

    output reg is_load,
    output reg is_alu_imm,
    output reg is_auipc,
    output reg is_store,
    output reg is_alu_reg,
    output reg is_lui,
    output reg is_branch,
    output reg is_jalr,
    output reg is_jal,
    output reg is_ret,
    output reg is_system,

    output [2:1] instr_len,

    output reg [3:0] alu_op,  // See tinyqv_alu for format

    output reg [2:0] mem_op,      // Bit 0 of mem_op indicates branch condition is reversed

    output reg [REG_ADDR_BITS-1:0] rs1,
    output reg [REG_ADDR_BITS-1:0] rs2,
    output reg [REG_ADDR_BITS-1:0] rd,

    output reg [2:0] additional_mem_ops,
    output reg       mem_op_increment_reg
);

    wire [31:0] Uimm = {    instr[31],   instr[30:12], {12{1'b0}}};
    wire [31:0] Iimm = {{21{instr[31]}}, instr[30:20]};
    wire [31:0] Simm = {{21{instr[31]}}, instr[30:25],instr[11:7]};
    wire [31:0] Bimm = {{20{instr[31]}}, instr[7],instr[30:25],instr[11:8],1'b0};
    wire [31:0] Jimm = {{12{instr[31]}}, instr[19:12],instr[20],instr[30:21],1'b0};

    // Compressed immediates
    wire [31:0] CLWSPimm     = {24'b0, instr[3:2], instr[12], instr[6:4], 2'b00};
    wire [31:0] CSWSPimm     = {24'b0, instr[8:7], instr[12:9], 2'b00};
    wire [31:0] CLSWimm      = {25'b0, instr[5], instr[12:10], instr[6], 2'b00};  // LW and SW
    wire [31:0] CLSHimm      = {30'b0, instr[5], 1'b0};  // LH(U) and SH
    wire [31:0] CLSBimm      = {30'b0, instr[5], instr[6]};  // LBU and SB
    wire [31:0] CJimm        = {{21{instr[12]}}, instr[8], instr[10:9], instr[6], instr[7], instr[2], instr[11], instr[5:3], 1'b0};
    wire [31:0] CBimm        = {{24{instr[12]}}, instr[6:5], instr[2], instr[11:10], instr[4:3], 1'b0};
    wire [31:0] CALUimm      = {{27{instr[12]}}, instr[6:2]};          // ADDI, LI, shifts, ANDI
    wire [31:0] CLUIimm      = {{15{instr[12]}}, instr[6:2], 12'b0};
    wire [31:0] CADDI16SPimm = {{23{instr[12]}}, instr[4:3], instr[5], instr[2], instr[6], 4'b0};
    wire [31:0] CADDI4SPimm  = {22'b0, instr[10:7], instr[12:11], instr[5], instr[6], 2'b0};
    wire [31:0] CSCXTimm     = {{23{instr[12]}}, instr[9:7], instr[10], instr[11], 4'b0};

    always @(*) begin
        additional_mem_ops = 3'b000;
        mem_op_increment_reg = 1;
        is_ret = 0;

        if (instr[1:0] == 2'b11) begin
            is_load    =  (instr[6:2] == 5'b00000); // rd <- mem[rs1+Iimm]
            is_alu_imm =  (instr[6:2] == 5'b00100); // rd <- rs1 OP Iimm
            is_auipc   =  (instr[6:2] == 5'b00101); // rd <- PC + Uimm
            is_store   =  (instr[6:2] == 5'b01000); // mem[rs1+Simm] <- rs2
            is_alu_reg =  (instr[6:2] == 5'b01100); // rd <- rs1 OP rs2
            is_lui     =  (instr[6:2] == 5'b01101); // rd <- Uimm
            is_branch  =  (instr[6:2] == 5'b11000); // if(rs1 OP rs2) PC<-PC+Bimm
            is_jalr    =  (instr[6:2] == 5'b11001); // rd <- PC+4; PC<-rs1+Iimm
            is_jal     =  (instr[6:2] == 5'b11011); // rd <- PC+4; PC<-PC+Jimm
            is_system  =  (instr[6:2] == 5'b11100); // rd <- csr - NYI

            // Determine immediate.  Hopefully muxing here is reasonable.
            if (is_auipc || is_lui) imm = Uimm;
            else if (is_store) imm = Simm;
            else if (is_branch) imm = Bimm;
            else if (is_jal) imm = Jimm;
            else imm = Iimm;

            // Determine alu op
            if (is_load || is_auipc || is_store || is_jalr || is_jal) alu_op = 4'b0000;  // ADD
            else if (is_branch) alu_op = {1'b0, !instr[14], instr[14:13]};
            else if (instr[26] && is_alu_reg) alu_op = {1'b1, instr[27:26], instr[13]};  // MUL or CZERO
            else alu_op = {instr[30] && (instr[5] || instr[13:12] == 2'b01),instr[14:12]};

            mem_op = instr[14:12];
            if ((is_load || is_store) && instr[13:12] == 2'b11) begin
                // TinyQV custom: 2 or 4 loads/stores to consecutive registers
                mem_op = 3'b010;
                additional_mem_ops = {1'b0, instr[14], 1'b1};
            end
            if (is_store && instr[14:12] == 3'b110) begin
                // TinyQV custom: 4 stores from the same reg (fast memset)
                mem_op = 3'b010;
                additional_mem_ops = {1'b0, instr[14], 1'b1};
                mem_op_increment_reg = 0;
            end

            rs1 = instr[15+:REG_ADDR_BITS];
            rs2 = instr[20+:REG_ADDR_BITS];
            rd  = instr[ 7+:REG_ADDR_BITS];
        end else begin
            is_load    = 0;
            is_alu_imm = 0;
            is_auipc   = 0;
            is_store   = 0;
            is_alu_reg = 0;
            is_lui     = 0;
            is_branch  = 0;
            is_jalr    = 0;
            is_jal     = 0;
            is_system  = 0;
            imm = {32{1'bx}};
            alu_op = 4'b0000;
            mem_op = 3'bxxx;
            rs1 = {REG_ADDR_BITS{1'bx}};
            rs2 = {REG_ADDR_BITS{1'bx}};
            rd = {REG_ADDR_BITS{1'bx}};

            case ({instr[1:0], instr[15:13]})
                5'b00000: begin // ADDI4SPN 
                    is_alu_imm = 1;
                    imm = CADDI4SPimm;
                    rs1 = 4'd2;
                    rd  = {1'b1, instr[4:2]};
                end
                5'b00010: begin // LW
                    is_load = 1;
                    mem_op = 3'b010;
                    imm = CLSWimm;
                    rs1 = {1'b1, instr[9:7]};
                    rd  = {1'b1, instr[4:2]};
                end 
                5'b00100: begin // Load/store byte or halfword
                    imm = instr[10] ? CLSHimm : CLSBimm;
                    rs1 = {1'b1, instr[9:7]};
                    if (instr[11]) begin
                        is_store = 1;
                        mem_op = {2'b00, instr[10]};
                        rs2 = {1'b1, instr[4:2]};
                    end else begin
                        is_load = 1;
                        mem_op = {~(instr[10] & instr[6]), 1'b0, instr[10]};
                        rd = {1'b1, instr[4:2]};
                    end
                end
                5'b00110: begin // SW
                    is_store = 1;
                    mem_op = 3'b010;
                    imm = CLSWimm;
                    rs1 = {1'b1, instr[9:7]};
                    rs2 = {1'b1, instr[4:2]};
                end
                5'b00111: begin // SCXT: Store rs2[2:0]+1 contiguous registers starting at {rs2[4:3], 3'b001}
                    is_store = 1;    //  from address imm(gp) (imm is a sign-extended 6-bit immediate multiplied by 16)
                    mem_op = 3'b010;
                    imm = CSCXTimm;
                    rs1 = 4'd3;
                    rs2 = {instr[5], 3'b001};
                    additional_mem_ops = instr[4:2];
                end
                5'b01000: begin // ADDI
                    is_alu_imm = 1;
                    imm = CALUimm;
                    rs1 = instr[10:7];
                    rd  = instr[10:7];
                end
                5'b01001: begin // JAL
                    is_jal = 1;
                    imm = CJimm;
                    rd  = 4'd1;
                end
                5'b01010: begin // LI
                    is_alu_imm = 1;
                    imm = CALUimm;
                    rs1 = 4'd0;
                    rd  = instr[10:7];
                end
                5'b01011: begin // ADDI16SP/LUI
                    rd  = instr[10:7];
                    if (instr[10:7] == 4'd2) begin
                        is_alu_imm = 1;
                        imm = CADDI16SPimm;
                        rs1 = 4'd2;
                    end else begin
                        is_lui = 1;
                        imm = CLUIimm;
                    end
                end
                5'b01100: begin // ALU
                    rs1 = {1'b1, instr[9:7]};
                    rs2 = {1'b1, instr[4:2]};
                    rd  = {1'b1, instr[9:7]};
                    imm = CALUimm;
                    if (instr[11:10] != 2'b11) begin
                        is_alu_imm = 1;
                        if (instr[11] == 1'b0) begin // SRx
                            alu_op = {instr[10], 3'b101};
                        end else begin
                            alu_op = 4'b0111;
                        end
                    end else if (instr[12]) begin
                        is_alu_imm = 1;
                        case (instr[4:2])
                            3'b101: begin  // NOT
                                    alu_op = 4'b0100; // XOR
                                    imm = 32'hffffffff;
                            end
                            default: begin // ZEXT
                                    alu_op = 4'b0111; // AND
                                    imm = {16'h0000, {8{instr[3]}}, 8'hff};
                            end
                        endcase
                        
                    end else begin
                        is_alu_reg = 1;
                        case (instr[6:5])
                            2'b00: alu_op = 4'b1000;  // SUB
                            2'b01: alu_op = 4'b0100;  // XOR
                            2'b10: alu_op = 4'b0110;  // OR
                            2'b11: alu_op = 4'b0111;  // AND
                        endcase
                    end
                end
                5'b01101: begin // J
                    is_jal = 1;
                    imm = CJimm;
                    rd  = 4'd0;
                end                
                5'b01110: begin // BEQZ
                    is_branch = 1;
                    imm = CBimm;
                    rs1 = {1'b1, instr[9:7]};
                    rs2 = 4'd0;
                    alu_op = 4'b0100;
                    mem_op = 3'b000;
                end    
                5'b01111: begin // BNEZ
                    is_branch = 1;
                    imm = CBimm;
                    rs1 = {1'b1, instr[9:7]};
                    rs2 = 4'd0;
                    alu_op = 4'b0100;
                    mem_op = 3'b001;
                end
                5'b10000: begin // SLLI
                    is_alu_imm = 1;
                    imm = CALUimm;
                    rs1 = instr[10:7];
                    rd  = instr[10:7];
                    alu_op = 4'b0001;
                end
                5'b10001: begin // LCXT: Load rd[2:0]+1 contiguous registers starting at {rd[4:3], 3'b001}
                    is_load = 1;     //  from address imm(gp) (imm is a sign-extended 6-bit immediate multiplied by 16)
                    mem_op = 3'b010;
                    imm = CADDI16SPimm;
                    rs1 = 4'd3;
                    rd  = {instr[10], 3'b001};
                    additional_mem_ops = instr[9:7];
                end
                5'b10010: begin // LWSP
                    is_load = 1;
                    mem_op = 3'b010;
                    imm = CLWSPimm;
                    rs1 = 4'd2;
                    rd  = instr[10:7];
                end
                5'b10011: begin // LWTP
                    is_load = 1;
                    mem_op = 3'b010;
                    imm = CLWSPimm;
                    rs1 = 4'd4;
                    rd  = instr[10:7];
                end
                5'b10100: begin 
                    if (instr[6:2] == 0) begin
                        if (instr[11:7] == 0) begin  // EBREAK
                            is_system = 1;
                            imm = 1;
                        end else begin // J(AL)R
                            if (instr[10:7] == 4'd1 && !instr[12]) is_ret = 1;
                            is_jalr = 1;
                            imm = 0;
                            rs1 = instr[10:7];
                            rd = {3'b000, instr[12]};
                        end
                    end else begin  // MV / ADD
                        is_alu_reg = 1;
                        rs1 = instr[12] ? instr[10:7] : 4'd0;
                        rs2 = instr[5:2];
                        rd  = instr[10:7];
                    end
                end
                5'b10101: begin // MUL16
                    is_alu_reg = 1;
                    alu_op = 4'b1010;
                    rs1 = instr[10:7];
                    rs2 = instr[5:2];
                    rd  = instr[10:7];                    
                end
                5'b10110: begin // SWSP
                    is_store = 1;
                    mem_op = 3'b010;
                    imm = CSWSPimm;
                    rs1 = 4'd2;
                    rs2 = instr[5:2];
                end
                5'b10111: begin // SWTP
                    is_store = 1;
                    mem_op = 3'b010;
                    imm = CSWSPimm;
                    rs1 = 4'd4;
                    rs2 = instr[5:2];
                end
                default: begin
                    is_system = 1;
                    imm = 32'd2;
                end
            endcase
        end
    end

    assign instr_len = (instr[1:0] == 2'b11) ? 2'b10 : 2'b01;

endmodule
