`default_nettype none

module decode (
    input  wire [31:0] i_inst,
    output wire [ 5:0] o_format,
    output wire        o_use_rs1,
    output wire        o_use_rs2,
    output wire        o_alu_pc,
    output wire        o_alu_imm,
    output wire [ 2:0] o_alu_op,
    output wire        o_alu_sub,
    output wire        o_alu_unsigned,
    output wire        o_alu_arith,
    output wire [ 1:0] o_wb_sel,
    output wire        o_reg_write,
    output wire        o_load,
    output wire        o_store,
    output wire        o_branch,
    output wire        o_jal,
    output wire        o_jalr,
    output wire        o_ebreak,
    output wire        o_illegal
);
    // split the instruction fields
    wire [6:0] opcode = i_inst[6:0];
    wire [2:0] funct3 = i_inst[14:12];
    wire [6:0] funct7 = i_inst[31:25];

    // one wire per instruction group
    wire is_reg    = (opcode == 7'b0110011);
    wire is_imm    = (opcode == 7'b0010011);
    wire is_load   = (opcode == 7'b0000011);
    wire is_store  = (opcode == 7'b0100011);
    wire is_branch = (opcode == 7'b1100011);
    wire is_lui    = (opcode == 7'b0110111);
    wire is_auipc  = (opcode == 7'b0010111);
    wire is_jal    = (opcode == 7'b1101111);
    wire is_jalr   = (opcode == 7'b1100111);

    // memory accesses already finish in order so fence has nothing extra to do
    wire is_fence = (opcode == 7'b0001111) & (funct3 == 3'b000);

    // check which funct values are allowed in each group
    wire reg_ok = (funct7 == 7'b0000000) |
                  ((funct7 == 7'b0100000) &
                   ((funct3 == 3'b000) | (funct3 == 3'b101)));
    wire imm_ok = (funct3 == 3'b001) ? (funct7 == 7'b0000000) :
                  (funct3 == 3'b101) ? ((funct7 == 7'b0000000) |
                                       (funct7 == 7'b0100000)) : 1'b1;
    wire load_ok = (funct3 == 3'b000) | (funct3 == 3'b001) |
                   (funct3 == 3'b010) | (funct3 == 3'b100) |
                   (funct3 == 3'b101);
    wire store_ok = (funct3 == 3'b000) | (funct3 == 3'b001) |
                    (funct3 == 3'b010);
    wire branch_ok = (funct3 == 3'b000) | (funct3 == 3'b001) |
                     (funct3 == 3'b100) | (funct3 == 3'b101) |
                     (funct3 == 3'b110) | (funct3 == 3'b111);

    // ebreak needs the whole instruction to match
    assign o_ebreak = (i_inst == 32'h00100073);

    // if none of these match then the instruction is illegal
    assign o_illegal = ~((is_reg & reg_ok) | (is_imm & imm_ok) |
                         (is_load & load_ok) | (is_store & store_ok) |
                         (is_branch & branch_ok) | is_lui | is_auipc |
                         is_jal | (is_jalr & (funct3 == 3'b000)) |
                         is_fence | o_ebreak);

    // select the format for imm.v, one bit per format
    assign o_format = (is_imm | is_load | is_jalr) ? 6'b000010 :
                      is_store                   ? 6'b000100 :
                      is_branch                  ? 6'b001000 :
                      (is_lui | is_auipc)         ? 6'b010000 :
                      is_jal                     ? 6'b100000 : 6'b000001;

    // which source registers we actually need
    assign o_use_rs1 = is_reg | is_imm | is_load | is_store | is_branch | is_jalr;
    assign o_use_rs2 = is_reg | is_store | is_branch;
    
    // select the alu inputs and operation
    assign o_alu_pc = is_auipc;
    assign o_alu_imm = is_imm | is_load | is_store | is_auipc | is_jalr;
    assign o_alu_op = (is_reg | is_imm) ? funct3 : 3'b000;

    // only sub should subtract, bit 30 is part of the immediate for addi
    assign o_alu_sub = is_reg & (funct3 == 3'b000) & i_inst[30];
    assign o_alu_unsigned = ((is_reg | is_imm) & (funct3 == 3'b011)) |
                            (is_branch & funct3[1]);
    assign o_alu_arith = (is_reg | is_imm) & (funct3 == 3'b101) & i_inst[30];
    
    // select what goes back into rd
    // 00 alu, 01 memory, 10 pc+4, 11 immediate
    assign o_wb_sel = is_load ? 2'b01 :
                      (is_jal | is_jalr) ? 2'b10 :
                      is_lui ? 2'b11 : 2'b00;

    // these instructions write a register
    assign o_reg_write = is_reg | is_imm | is_load | is_lui | is_auipc |
                         is_jal | is_jalr;
                         
    // memory and branch outputs
    assign o_load = is_load;
    assign o_store = is_store;
    assign o_branch = is_branch;
    assign o_jal = is_jal;
    assign o_jalr = is_jalr;
endmodule

`default_nettype wire
