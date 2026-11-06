module hart #(
    // After reset, the program counter (PC) should be initialized to this
    // address and start executing instructions from there.
    parameter RESET_ADDR = 32'h00000000
) (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset.
    input  wire        i_rst,
    // Instruction fetch goes through a read only instruction memory (imem)
    // port. The port accepts a 32-bit address (e.g. from the program counter)
    // per cycle and combinationally returns a 32-bit instruction word. This
    // is not representative of a realistic memory interface; it has been
    // modeled as more similar to a DFF or SRAM to simplify phase 3. In
    // later phases, you will replace this with a more realistic memory.
    //
    // 32-bit read address for the instruction memory. This is expected to be
    // 4 byte aligned - that is, the two LSBs should be zero.
    output wire [31:0] o_imem_raddr,
    // Instruction word fetched from memory, available on the same cycle.
    input  wire [31:0] i_imem_rdata,
    // Data memory accesses go through a separate read/write data memory (dmem)
    // that is shared between read (load) and write (stored). The port accepts
    // a 32-bit address, read or write enable, and mask (explained below) each
    // cycle. Reads are combinational - values are available immediately after
    // updating the address and asserting read enable. Writes occur on (and
    // are visible at) the next clock edge.
    //
    // Read/write address for the data memory. This should be 32-bit aligned
    // (i.e. the two LSB should be zero). See `o_dmem_mask` for how to perform
    // half-word and byte accesses at unaligned addresses.
    output wire [31:0] o_dmem_addr,
    // When asserted, the memory will perform a read at the aligned address
    // specified by `i_addr` and return the 32-bit word at that address
    // immediately (i.e. combinationally). It is illegal to assert this and
    // `o_dmem_wen` on the same cycle.
    output wire        o_dmem_ren,
    // When asserted, the memory will perform a write to the aligned address
    // `o_dmem_addr`. When asserted, the memory will write the bytes in
    // `o_dmem_wdata` (specified by the mask) to memory at the specified
    // address on the next rising clock edge. It is illegal to assert this and
    // `o_dmem_ren` on the same cycle.
    output wire        o_dmem_wen,
    // The 32-bit word to write to memory when `o_dmem_wen` is asserted. When
    // write enable is asserted, the byte lanes specified by the mask will be
    // written to the memory word at the aligned address at the next rising
    // clock edge. The other byte lanes of the word will be unaffected.
    output wire [31:0] o_dmem_wdata,
    // The dmem interface expects word (32 bit) aligned addresses. However,
    // the processor supports byte and half-word loads and stores at unaligned and
    // 16-bit aligned addresses, respectively. To support this, the access
    // mask specifies which bytes within the 32-bit word are actually read
    // from or written to memory.
    //
    // To perform a half-word read at address 0x00001002, align `o_dmem_addr`
    // to 0x00001000, assert `o_dmem_ren`, and set the mask to 0b1100 to
    // indicate that only the upper two bytes should be read. Only the upper
    // two bytes of `i_dmem_rdata` can be assumed to have valid data; to
    // calculate the final value of the `lh[u]` instruction, shift the rdata
    // word right by 16 bits and sign/zero extend as appropriate.
    //
    // To perform a byte write at address 0x00002003, align `o_dmem_addr` to
    // `0x00002000`, assert `o_dmem_wen`, and set the mask to 0b1000 to
    // indicate that only the upper byte should be written. On the next clock
    // cycle, the upper byte of `o_dmem_wdata` will be written to memory, with
    // the other three bytes of the aligned word unaffected. Remember to shift
    // the value of the `sb` instruction left by 24 bits to place it in the
    // appropriate byte lane.
    output wire [ 3:0] o_dmem_mask,
    // The 32-bit word read from data memory. When `o_dmem_ren` is asserted,
    // this will immediately reflect the contents of memory at the specified
    // address, for the bytes enabled by the mask. When read enable is not
    // asserted, or for bytes not set in the mask, the value is undefined.
    input  wire [31:0] i_dmem_rdata,
	// The output `retire` interface is used to signal to the testbench that
    // the CPU has completed and retired an instruction. A single cycle
    // implementation will assert this every cycle; however, a pipelined
    // implementation that needs to stall (due to internal hazards or waiting
    // on memory accesses) will not assert the signal on cycles where the
    // instruction in the writeback stage is not retiring.
    //
    // Asserted when an instruction is being retired this cycle. If this is
    // not asserted, the other retire signals are ignored and may be left invalid.
    output wire        o_retire_valid,
    // The 32 bit instruction word of the instrution being retired. This
    // should be the unmodified instruction word fetched from instruction
    // memory.
    output wire [31:0] o_retire_inst,
    // Asserted if the instruction produced a trap, due to an illegal
    // instruction, unaligned data memory access, or unaligned instruction
    // address on a taken branch or jump.
    output wire        o_retire_trap,
    // Asserted if the instruction is an `ebreak` instruction used to halt the
    // processor. This is used for debugging and testing purposes to end
    // a program.
    output wire        o_retire_halt,
    // The first register address read by the instruction being retired. If
    // the instruction does not read from a register (like `lui`), this is
    // don't-care -- the grading testbench doesn't look at it in that case.
    output wire [ 4:0] o_retire_rs1_raddr,
    // The second register address read by the instruction being retired. If
    // the instruction does not read from a second register (like `addi`),
    // this is don't-care -- the grading testbench doesn't look at it in that
    // case.
    output wire [ 4:0] o_retire_rs2_raddr,
    // The first source register data read from the register file (in the
    // decode stage) for the instruction being retired. If rs1 is 5'd0, this
    // should also be 32'd0.
    output wire [31:0] o_retire_rs1_rdata,
    // The second source register data read from the register file (in the
    // decode stage) for the instruction being retired. If rs2 is 5'd0, this
    // should also be 32'd0.
    output wire [31:0] o_retire_rs2_rdata,
    // The destination register address written by the instruction being
    // retired. If the instruction does not write to a register (like `sw`),
    // this should be 5'd0.
    output wire [ 4:0] o_retire_rd_waddr,
    // The destination register data written to the register file in the
    // writeback stage by this instruction. If rd is 5'd0, this field is
    // ignored and can be treated as a don't care.
    output wire [31:0] o_retire_rd_wdata,
    output wire [31:0] o_retire_dmem_addr,
    output wire [ 3:0] o_retire_dmem_mask,
    output wire        o_retire_dmem_ren,
    output wire        o_retire_dmem_wen,
    output wire [31:0] o_retire_dmem_rdata,
    output wire [31:0] o_retire_dmem_wdata,
    // The current program counter of the instruction being retired - i.e.
    // the instruction memory address that the instruction was fetched from.
    output wire [31:0] o_retire_pc,
    // the next program counter after the instruction is retired. For most
    // instructions, this is `o_retire_pc + 4`, but must be the branch or jump
    // target for *taken* branches and jumps.
    output wire [31:0] o_retire_next_pc

`ifdef RISCV_FORMAL
    ,`RVFI_OUTPUTS,
`endif
);
    // 1. FETCH:
    reg  [31:0] pc;
    wire [31:0] next_pc;
    wire        halt;

    // declared here so every use is below the declaration
    wire redirect;
    wire hazard_detect;
    reg id_ex_op_load;
    wire [31:0] executeRs1Data;
    wire [31:0] executeRs2Data;
    reg halted;
    reg id_ex_if_id_flag;
    reg [ 4:0] id_ex_rd;
    reg id_ex_uses_rd;
    reg ex_mem_id_ex_if_id_flag;
    reg ex_mem_id_ex_uses_rd;
    reg [ 4:0] ex_mem_id_ex_rd;
    reg mem_wb_ex_mem_id_ex_if_id_flag;
    reg mem_wb_ex_mem_id_ex_uses_rd;
    reg [ 4:0] mem_wb_ex_mem_id_ex_rd;

    always @(posedge i_clk) begin
        if (i_rst)
            pc <= RESET_ADDR;
        else if (!halt && !halted && (redirect || !hazard_detect))
            pc <= next_pc;
    end

    assign o_imem_raddr = pc;

    wire [31:0] inst    = i_imem_rdata;

    wire [31:0] pc_plus4 = pc + 32'd4;

    // IF/ID registers
    reg [31:0] if_id_inst; // save into ID/EX for retirement
    reg [31:0] if_id_pc; // save into ID/EX as this instruction's PC
    reg if_id_flag; // save into ID/EX as incoming validity


    always @(posedge i_clk) begin
        // redirect describes the flush behaivour
        // it is declared in EX stage
        if(i_rst || redirect || halted || halt) begin
            if_id_flag <= 0;
            // others are ignored while this flag is invalid
        end
        else if (!hazard_detect) begin
            if_id_flag <= 1;
            if_id_pc <= pc;
            if_id_inst <= inst;
        end
    end

    // decide what to do with these values in case of stall or flush




    // 2. DECODE: split the instruction into its encoded fields.
    // wire [6:0] opcode = inst[6:0];
    // wire [4:0] rd     = inst[11:7];
    // wire [2:0] funct3 = inst[14:12];
    // wire [4:0] rs1    = inst[19:15];
    // wire [4:0] rs2    = inst[24:20];
    // wire [6:0] funct7 = inst[31:25];

    // update decode to work with our IF/ID registers
    wire [6:0] opcode = if_id_inst[6:0];
    wire [4:0] rd     = if_id_inst[11:7]; // save
    wire [2:0] funct3 = if_id_inst[14:12]; // save
    wire [4:0] rs1    = if_id_inst[19:15];
    wire [4:0] rs2    = if_id_inst[24:20];
    wire [6:0] funct7 = if_id_inst[31:25];

    wire op_lui    = (opcode == 7'b0110111); // save
    wire op_auipc  = (opcode == 7'b0010111); // save
    wire op_jal    = (opcode == 7'b1101111); // save
    wire op_jalr   = (opcode == 7'b1100111); // save
    wire op_branch = (opcode == 7'b1100011); // save
    wire op_load   = (opcode == 7'b0000011); // save
    wire op_store  = (opcode == 7'b0100011); // save
    wire op_imm    = (opcode == 7'b0010011); // save
    wire op_reg    = (opcode == 7'b0110011); // save
    wire op_fence  = (opcode == 7'b0001111);
    wire op_system = (opcode == 7'b1110011);

    wire is_ebreak = (if_id_inst == 32'h00100073); // save
    wire is_ecall  = (if_id_inst == 32'h00000073);

    // check the supported encodings within each instruction family
    wire funct7_zero = (funct7 == 7'b0000000);
    wire funct7_alt  = (funct7 == 7'b0100000);
    wire reg_legal   = funct7_zero | (funct7_alt & ((funct3 == 3'b000) | (funct3 == 3'b101)));
    wire imm_legal   = ((funct3 == 3'b001) & funct7_zero) |
                       ((funct3 == 3'b101) & (funct7_zero | funct7_alt)) |
                       ((funct3 != 3'b001) & (funct3 != 3'b101));
    wire load_legal  = (funct3 != 3'b011) & (funct3 != 3'b110) & (funct3 != 3'b111);
    wire store_legal = (funct3 == 3'b000) | (funct3 == 3'b001) | (funct3 == 3'b010);
    wire br_legal    = (funct3 != 3'b010) & (funct3 != 3'b011);
    wire jalr_legal  = (funct3 == 3'b000);

    wire illegal = ~((op_lui) | (op_auipc) | (op_jal) |
                     (op_jalr & jalr_legal) |
                     (op_branch & br_legal) |
                     (op_load & load_legal) |
                     (op_store & store_legal) |
                     (op_imm & imm_legal) |
                     (op_reg & reg_legal) |
                     (op_fence) |
                     (op_system & (is_ebreak | is_ecall)));

    // describe the register operands that this instruction really uses
    wire uses_rs1 = op_jalr | op_branch | op_load | op_store | op_imm | op_reg;
    wire uses_rs2 = op_branch | op_store | op_reg;
    wire uses_rd  = op_lui | op_auipc | op_jal | op_jalr | op_load | op_imm | op_reg; // save

    // read x0 when a source is unused
    wire [4:0] rs1_raddr = uses_rs1 ? rs1 : 5'd0; // save
    wire [4:0] rs2_raddr = uses_rs2 ? rs2 : 5'd0; // save

    // tell imm.v how the immediate bits are arranged
    // concatenation lists the highest bit first: {J, U, B, S, I, R}
    wire [5:0] format = {op_jal,
                         op_lui | op_auipc,
                         op_branch,
                         op_store,
                         op_jalr | op_load | op_imm,
                         op_reg};

    // expand the instruction's immediate constant or offset to 32 bits
    wire [31:0] immediate; // save
    imm u_imm (
        .i_inst      (if_id_inst),
        .i_format    (format),
        .o_immediate (immediate)
    );

    wire [31:0] rs1_rdata, rs2_rdata; // save both
    wire        rd_wen;
    wire [ 4:0] rd_waddr;
    wire [31:0] rd_wdata;

    rf #(
        .BYPASS_EN (1)
    ) u_rf (
        .i_clk       (i_clk),
        .i_rst       (i_rst),
        .i_rs1_raddr (rs1_raddr),
        .o_rs1_rdata (rs1_rdata),
        .i_rs2_raddr (rs2_raddr),
        .o_rs2_rdata (rs2_rdata),
        .i_rd_wen    (rd_wen),
        .i_rd_waddr  (rd_waddr),
        .i_rd_wdata  (rd_wdata)
    );


    wire loadUseHazard = id_ex_if_id_flag & id_ex_op_load & (id_ex_rd != 5'd0) &
                         ((rs1_raddr == id_ex_rd) | (rs2_raddr == id_ex_rd));

    assign hazard_detect = if_id_flag & loadUseHazard;


    // ID/EX registers
    // if_id_flag 1
    // if_id_inst 32
    reg [31:0] id_ex_if_id_inst;
    // if_id_pc 32
    reg [31:0] id_ex_if_id_pc;
    // rs1_rdata 32
    reg [31:0] id_ex_rs1_rdata;
    // rs2_rdata 32
    reg [31:0] id_ex_rs2_rdata;
    // rs1_raddr 5
    reg [ 4:0] id_ex_rs1_raddr;
    // rs2_raddr 5
    reg [ 4:0] id_ex_rs2_raddr;
    // rd 5
    // immediate 32
    reg [31:0] id_ex_immediate;
    // uses_rd 1
    // op_auipc 1
    reg id_ex_op_auipc;
    // op_imm 1
    reg id_ex_op_imm;
    // op_reg 1
    reg id_ex_op_reg;
    // funct3 3
    reg [ 2:0] id_ex_funct3;
    // op_branch 1
    reg id_ex_op_branch;
    // op_jal 1
    reg id_ex_op_jal;
    // op_jalr 1
    reg id_ex_op_jalr;
    // op_store 1
    reg id_ex_op_store;
    // op_lui 1
    reg id_ex_op_lui;
    // illegal 1
    reg id_ex_illegal;
    // is_ebreak 1
    reg id_ex_is_ebreak;

    always @(posedge i_clk) begin
        // redirect is for flushing the register
        if(i_rst || redirect || halted || halt || hazard_detect) begin
            // again clearing this should be enough
            id_ex_if_id_flag <= 0;
        end
        else begin
            // this flag should carry over from the previous one
            id_ex_if_id_flag <= if_id_flag;

            // save the rest of the set values
            id_ex_if_id_inst <= if_id_inst;
            id_ex_if_id_pc <= if_id_pc;
            id_ex_rs1_rdata <= rs1_rdata;
            id_ex_rs2_rdata <= rs2_rdata;
            id_ex_rs1_raddr <= rs1_raddr;
            id_ex_rs2_raddr <= rs2_raddr;
            id_ex_rd <= rd;
            id_ex_immediate <= immediate;
            id_ex_uses_rd <= uses_rd;
            id_ex_op_auipc <= op_auipc;
            id_ex_op_imm <= op_imm;
            id_ex_op_reg <= op_reg;
            id_ex_funct3 <= funct3;
            id_ex_op_branch <= op_branch;
            id_ex_op_jal <= op_jal;
            id_ex_op_jalr <= op_jalr;
            id_ex_op_load <= op_load;
            id_ex_op_store <= op_store;
            id_ex_op_lui <= op_lui;
            id_ex_illegal <= illegal;
            id_ex_is_ebreak <= is_ebreak;
        end
    end

    // 3. EXECUTE: select the ALU operation and its two input values
    // this is our ALU control panel
    wire       alu_funct = id_ex_op_reg | id_ex_op_imm;
    wire [2:0] alu_opsel = alu_funct ? id_ex_funct3 : 3'b000;
    wire       alu_sub   = id_ex_op_reg & id_ex_if_id_inst[30] & (id_ex_funct3 == 3'b000);
    wire       alu_arith = alu_funct & id_ex_if_id_inst[30];
    wire       alu_unsigned = id_ex_op_branch ? id_ex_funct3[1] : (id_ex_funct3 == 3'b011);

    wire [31:0] alu_op1 = id_ex_op_auipc ? id_ex_if_id_pc : executeRs1Data;
    wire [31:0] alu_op2 = (id_ex_op_reg | id_ex_op_branch) ? executeRs2Data : id_ex_immediate;


    // ALU also provides equality and less than comparisons for branches
    wire [31:0] alu_result; // save
    wire        alu_eq, alu_slt;
    

    alu u_alu (
        .i_opsel    (alu_opsel),
        .i_sub      (alu_sub),
        .i_unsigned (alu_unsigned),
        .i_arith    (alu_arith),
        .i_op1      (alu_op1),
        .i_op2      (alu_op2),
        .o_result   (alu_result),
        .o_eq       (alu_eq),
        .o_slt      (alu_slt)
    );

    // handle branch cases
    wire br_cond  = id_ex_funct3[2] ? alu_slt : alu_eq;
    wire br_taken = id_ex_op_branch & (br_cond ^ id_ex_funct3[0]);

    // branches and JAL use PC + offset. JALR uses rs1 + offset from the ALU
    // they now should use saved pc + offset
    wire [31:0] pc_target   = id_ex_if_id_pc + id_ex_immediate;
    wire [31:0] jalr_target = {alu_result[31:1], 1'b0};
    wire [31:0] jump_target = id_ex_op_jalr ? jalr_target : pc_target;
    // and it with the valid flag to make sure that the instruction is valid
    // we are going to use this as our flush switch as well since it already identifies the flush behaveour
    assign redirect = (br_taken | id_ex_op_jal | id_ex_op_jalr) & id_ex_if_id_flag;

    // branch is resolved in EX stage
    assign next_pc = redirect ? jump_target : pc_plus4;
    
    // this is where we have to disregard child fetched instructions and flush the pipeline
    // simply we just reset the previous registers in the next posedge


    wire [31:0] ex_next_pc = redirect ? jump_target : (id_ex_if_id_pc + 32'd4);

    wire inst_misaligned = redirect & (jump_target[1:0] != 2'b00);

    // EX/MEM register
    // alu_result 32
    reg [31:0] ex_mem_alu_result;
    // id_ex_rs2_rdata 32
    reg [31:0] ex_mem_id_ex_rs2_rdata;
    // id_ex_immediate 32
    reg [31:0] ex_mem_id_ex_immediate;
    // id_ex_funct3 3
    reg [2:0] ex_mem_id_ex_funct3;
    // id_ex_op_load 1
    reg ex_mem_id_ex_op_load;
    // id_ex_op_store 1
    reg ex_mem_id_ex_op_store;
    // id_ex_illegal 1
    reg ex_mem_id_ex_illegal;
    // id_ex_op_lui 1
    reg ex_mem_id_ex_op_lui;
    // id_ex_op_jal 1
    reg ex_mem_id_ex_op_jal;
    // id_ex_op_jalr 1
    reg ex_mem_id_ex_op_jalr;

    // id_ex_uses_rd 1
    // id_ex_is_ebreak 1
    reg ex_mem_id_ex_is_ebreak;
    // id_ex_rd 5
    // reg [4:0] ex_mem_id_ex_rd;
    // id_ex_if_id_pc 32
    reg [31:0] ex_mem_id_ex_if_id_pc;

    // id_ex_if_id_inst 32
    reg [31:0] ex_mem_id_ex_if_id_inst;
    // id_ex_rs1_rdata 32
    reg [31:0] ex_mem_id_ex_rs1_rdata;
    // id_ex_rs1_raddr 5
    reg [4:0] ex_mem_id_ex_rs1_raddr;
    // id_ex_rs2_raddr 5
    reg [4:0] ex_mem_id_ex_rs2_raddr;
    
    // inst_misaligned 1
    reg ex_mem_inst_misaligned;
    // ex_next_pc 32
    reg [31:0] ex_mem_ex_next_pc;

    // id_ex_if_id_flag 1
    // reg ex_mem_id_ex_if_id_flag;

    // id_ex_if_id_flag 1
    // reg ex_mem_id_ex_if_id_flag;

    always @(posedge i_clk) begin
        if (i_rst || halted || halt) begin
            ex_mem_id_ex_if_id_flag <= 1'b0;
        end
        else begin
            ex_mem_id_ex_if_id_flag <= id_ex_if_id_flag;

            ex_mem_alu_result <= alu_result;
            ex_mem_id_ex_rs2_rdata <= executeRs2Data;
            ex_mem_id_ex_immediate <= id_ex_immediate;
            ex_mem_id_ex_funct3 <= id_ex_funct3;
            ex_mem_id_ex_op_load <= id_ex_op_load;
            ex_mem_id_ex_op_store <= id_ex_op_store;
            ex_mem_id_ex_illegal <= id_ex_illegal;
            ex_mem_id_ex_op_lui <= id_ex_op_lui;
            ex_mem_id_ex_op_jal <= id_ex_op_jal;
            ex_mem_id_ex_op_jalr <= id_ex_op_jalr;

            ex_mem_id_ex_uses_rd <= id_ex_uses_rd;
            ex_mem_id_ex_is_ebreak <= id_ex_is_ebreak;
            ex_mem_id_ex_rd <= id_ex_rd;
            ex_mem_id_ex_if_id_pc <= id_ex_if_id_pc;

            ex_mem_id_ex_if_id_inst <= id_ex_if_id_inst;
            ex_mem_id_ex_rs1_rdata <= executeRs1Data;
            ex_mem_id_ex_rs1_raddr <= id_ex_rs1_raddr;
            ex_mem_id_ex_rs2_raddr <= id_ex_rs2_raddr;

            ex_mem_inst_misaligned <= inst_misaligned;
            ex_mem_ex_next_pc <= ex_next_pc;
        end
    end


    // 4. MEMORY: the ALU result is the effective load/store byte address
    
    wire [1:0] byte_off  = ex_mem_alu_result[1:0];
    wire       size_byte = (ex_mem_id_ex_funct3[1:0] == 2'b00);
    wire       size_half = (ex_mem_id_ex_funct3[1:0] == 2'b01);
    wire       size_word = (ex_mem_id_ex_funct3[1:0] == 2'b10);

    wire mem_access     = ex_mem_id_ex_op_load | ex_mem_id_ex_op_store;
    wire mem_misaligned = mem_access & ((size_half & byte_off[0]) |
                                        (size_word & (byte_off != 2'b00)));

    wire trap = ex_mem_id_ex_illegal | ex_mem_inst_misaligned | mem_misaligned;

    wire memoryWritesRegister = ex_mem_id_ex_if_id_flag & ex_mem_id_ex_uses_rd & (ex_mem_id_ex_rd != 5'd0) & ~trap;
    wire [31:0] memoryForwardData = ex_mem_id_ex_op_lui ? ex_mem_id_ex_immediate :
                                    (ex_mem_id_ex_op_jal | ex_mem_id_ex_op_jalr) ? (ex_mem_id_ex_if_id_pc + 32'd4) :
                                                                                    ex_mem_alu_result;

    wire forwardRs1FromMemory = memoryWritesRegister & (ex_mem_id_ex_rd == id_ex_rs1_raddr);
    wire forwardRs2FromMemory = memoryWritesRegister & (ex_mem_id_ex_rd == id_ex_rs2_raddr);
    wire forwardRs1FromWriteback = (rd_waddr != 5'd0) & (rd_waddr == id_ex_rs1_raddr);
    wire forwardRs2FromWriteback = (rd_waddr != 5'd0) & (rd_waddr == id_ex_rs2_raddr);

    assign executeRs1Data = forwardRs1FromMemory ? memoryForwardData : forwardRs1FromWriteback ? rd_wdata : id_ex_rs1_rdata;
    assign executeRs2Data = forwardRs2FromMemory ? memoryForwardData :forwardRs2FromWriteback ? rd_wdata : id_ex_rs2_rdata;

    wire [3:0] mask_byte = (byte_off == 2'b00) ? 4'b0001 :
                           (byte_off == 2'b01) ? 4'b0010 :
                           (byte_off == 2'b10) ? 4'b0100 :
                                                 4'b1000;
    wire [3:0] mask_half = byte_off[1] ? 4'b1100 : 4'b0011;
    wire [3:0] mem_mask  = size_byte ? mask_byte :
                           size_half ? mask_half :
                                       4'b1111;

    wire [31:0] store_data = (byte_off == 2'b00) ? ex_mem_id_ex_rs2_rdata :
                             (byte_off == 2'b01) ? {ex_mem_id_ex_rs2_rdata[23:0], 8'b0} :
                             (byte_off == 2'b10) ? {ex_mem_id_ex_rs2_rdata[15:0], 16'b0} :
                                                   {ex_mem_id_ex_rs2_rdata[7:0], 24'b0};

    assign o_dmem_addr  = {ex_mem_alu_result[31:2], 2'b00};

    assign o_dmem_ren   = ex_mem_id_ex_op_load & ~trap & ex_mem_id_ex_if_id_flag & ~i_rst & ~halt & ~halted;
    assign o_dmem_wen   = ex_mem_id_ex_op_store & ~trap & ex_mem_id_ex_if_id_flag & ~i_rst & ~halt & ~halted;
    assign o_dmem_wdata = store_data;
    assign o_dmem_mask  = (o_dmem_ren | o_dmem_wen) ? mem_mask : 4'b0000;

    wire [31:0] load_shifted = (byte_off == 2'b00) ? i_dmem_rdata :
                               (byte_off == 2'b01) ? {8'b0, i_dmem_rdata[31:8]} :
                               (byte_off == 2'b10) ? {16'b0, i_dmem_rdata[31:16]} :
                                                     {24'b0, i_dmem_rdata[31:24]};

    wire        load_sign = ~ex_mem_id_ex_funct3[2];
    wire [31:0] load_byte = {{24{load_sign & load_shifted[7]}}, load_shifted[7:0]};
    wire [31:0] load_half = {{16{load_sign & load_shifted[15]}}, load_shifted[15:0]};
    wire [31:0] load_data = size_byte ? load_byte :
                            size_half ? load_half :
                                        load_shifted;

    // MEM/WB register

    // ex_mem_id_ex_op_lui 1
    reg mem_wb_ex_mem_id_ex_op_lui;
    // ex_mem_id_ex_immediate 32
    reg [31:0] mem_wb_ex_mem_id_ex_immediate;
    // ex_mem_ex_next_pc 32
    reg [31:0] mem_wb_ex_mem_ex_next_pc;
    // ex_mem_id_ex_op_jal 1
    reg mem_wb_ex_mem_id_ex_op_jal;
    // ex_mem_id_ex_op_jalr 1
    reg mem_wb_ex_mem_id_ex_op_jalr;
    // ex_mem_id_ex_op_load 1
    reg mem_wb_ex_mem_id_ex_op_load;
    // load_data 32
    reg [31:0] mem_wb_load_data;
    // ex_mem_alu_result 32
    reg [31:0] mem_wb_ex_mem_alu_result;
    // ex_mem_id_ex_uses_rd 1
    // reg mem_wb_ex_mem_id_ex_uses_rd;
    // trap 1
    reg mem_wb_trap;
    // ex_mem_id_ex_is_ebreak 1
    reg mem_wb_ex_mem_id_ex_is_ebreak;

    // ex_mem_id_ex_rs1_raddr 5
    reg [4:0] mem_wb_ex_mem_id_ex_rs1_raddr;
    // ex_mem_id_ex_rs2_raddr 5
    reg [4:0] mem_wb_ex_mem_id_ex_rs2_raddr;
    // ex_mem_id_ex_rs1_rdata 32
    reg [31:0] mem_wb_ex_mem_id_ex_rs1_rdata;
    // ex_mem_id_ex_rs2_rdata 32
    reg [31:0] mem_wb_ex_mem_id_ex_rs2_rdata;
    // ex_mem_id_ex_if_id_pc 32
    reg [31:0] mem_wb_ex_mem_id_ex_if_id_pc;
    // ex_mem_id_ex_if_id_inst 32
    reg [31:0] mem_wb_ex_mem_id_ex_if_id_inst;
    // ex_mem_id_ex_if_id_flag 1
    // reg mem_wb_ex_mem_id_ex_if_id_flag;
    // ex_mem_id_ex_if_id_flag 1
    // reg mem_wb_ex_mem_id_ex_if_id_flag;

    // o_dmem_addr 32
    reg [31:0] mem_wb_dmem_addr;
    // o_dmem_mask 4
    reg [3:0] mem_wb_dmem_mask;
    // o_dmem_ren 1
    reg mem_wb_dmem_ren;
    // o_dmem_wen 1
    reg mem_wb_dmem_wen;
    // i_dmem_rdata 32
    reg [31:0] mem_wb_dmem_rdata;
    // o_dmem_wdata 32
    reg [31:0] mem_wb_dmem_wdata;

    always @(posedge i_clk) begin
        if (i_rst || halted || halt) begin
            mem_wb_ex_mem_id_ex_if_id_flag <= 1'b0;
        end
        else begin
            mem_wb_ex_mem_id_ex_if_id_flag <= ex_mem_id_ex_if_id_flag;

            mem_wb_ex_mem_id_ex_op_lui <= ex_mem_id_ex_op_lui;
            mem_wb_ex_mem_id_ex_immediate <= ex_mem_id_ex_immediate;
            mem_wb_ex_mem_ex_next_pc <= ex_mem_ex_next_pc;
            mem_wb_ex_mem_id_ex_op_jal <= ex_mem_id_ex_op_jal;
            mem_wb_ex_mem_id_ex_op_jalr <= ex_mem_id_ex_op_jalr;
            mem_wb_ex_mem_id_ex_op_load <= ex_mem_id_ex_op_load;
            mem_wb_load_data <= load_data;
            mem_wb_ex_mem_alu_result <= ex_mem_alu_result;
            mem_wb_ex_mem_id_ex_uses_rd <= ex_mem_id_ex_uses_rd;
            mem_wb_trap <= trap;
            mem_wb_ex_mem_id_ex_rd <= ex_mem_id_ex_rd;
            mem_wb_ex_mem_id_ex_is_ebreak <= ex_mem_id_ex_is_ebreak;
            mem_wb_ex_mem_id_ex_rs1_raddr <= ex_mem_id_ex_rs1_raddr;
            mem_wb_ex_mem_id_ex_rs2_raddr <= ex_mem_id_ex_rs2_raddr;
            mem_wb_ex_mem_id_ex_rs1_rdata <= ex_mem_id_ex_rs1_rdata;
            mem_wb_ex_mem_id_ex_rs2_rdata <= ex_mem_id_ex_rs2_rdata;
            mem_wb_ex_mem_id_ex_if_id_pc <= ex_mem_id_ex_if_id_pc;
            mem_wb_ex_mem_id_ex_if_id_inst <= ex_mem_id_ex_if_id_inst;
            mem_wb_dmem_addr <= o_dmem_addr;
            mem_wb_dmem_mask <= o_dmem_mask;
            mem_wb_dmem_ren <= o_dmem_ren;
            mem_wb_dmem_wen <= o_dmem_wen;
            mem_wb_dmem_rdata <= i_dmem_rdata;
            mem_wb_dmem_wdata <= o_dmem_wdata;
        end
    end

    // 5. WRITEBACK: choose what the destination register receives
    assign rd_wdata = mem_wb_ex_mem_id_ex_op_lui ? mem_wb_ex_mem_id_ex_immediate :
                      (mem_wb_ex_mem_id_ex_op_jal | mem_wb_ex_mem_id_ex_op_jalr) ? (mem_wb_ex_mem_id_ex_if_id_pc + 32'd4) :
                      mem_wb_ex_mem_id_ex_op_load ? mem_wb_load_data :
                                                    mem_wb_ex_mem_alu_result;

    // no destination or a trap means no write. Writes to x0 are also disabled
    assign rd_waddr = (mem_wb_ex_mem_id_ex_uses_rd & ~mem_wb_trap & mem_wb_ex_mem_id_ex_if_id_flag) ? mem_wb_ex_mem_id_ex_rd : 5'd0;
    assign rd_wen   = (rd_waddr != 5'd0) & ~halted & ~i_rst;

    // EBREAK holds the PC
    assign halt = mem_wb_ex_mem_id_ex_is_ebreak & mem_wb_ex_mem_id_ex_if_id_flag;

    // reg halted;

    always @(posedge i_clk) begin
        if (i_rst)
            halted <= 1'b0;
        else if (halt)
            halted <= 1'b1;
    end

    // RETIREMENT:
    assign o_retire_valid     = mem_wb_ex_mem_id_ex_if_id_flag & ~halted & ~i_rst;
    assign o_retire_inst      = mem_wb_ex_mem_id_ex_if_id_inst;
    assign o_retire_trap      = mem_wb_trap;
    assign o_retire_halt      = halt;
    assign o_retire_rs1_raddr = mem_wb_ex_mem_id_ex_rs1_raddr;
    assign o_retire_rs1_rdata = mem_wb_ex_mem_id_ex_rs1_rdata;
    assign o_retire_rs2_raddr = mem_wb_ex_mem_id_ex_rs2_raddr;
    assign o_retire_rs2_rdata = mem_wb_ex_mem_id_ex_rs2_rdata;
    assign o_retire_rd_waddr  = rd_waddr;
    assign o_retire_rd_wdata  = rd_wdata;
    assign o_retire_dmem_addr  = mem_wb_dmem_addr;
    assign o_retire_dmem_ren   = o_retire_valid & mem_wb_dmem_ren;
    assign o_retire_dmem_wen   = o_retire_valid & mem_wb_dmem_wen;
    assign o_retire_dmem_mask  = (o_retire_dmem_ren | o_retire_dmem_wen) ? mem_wb_dmem_mask : 4'b0000;
    assign o_retire_dmem_rdata = mem_wb_dmem_rdata;
    assign o_retire_dmem_wdata = mem_wb_dmem_wdata;
    assign o_retire_pc        = mem_wb_ex_mem_id_ex_if_id_pc;
    assign o_retire_next_pc   = mem_wb_ex_mem_ex_next_pc;
endmodule

`default_nettype wire
