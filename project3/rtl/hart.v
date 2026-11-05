`default_nettype none

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
    // Fetch and state. All architectural updates occur at the rising edge;
    // the combinational path executes one instruction between clock edges.
    reg [31:0] pc;
    reg halted;
    wire active = ~i_rst & ~halted;
    wire [31:0] inst = i_imem_rdata;
    wire [31:0] pc4 = pc + 32'd4;
    wire [31:0] next_pc;
    wire ebreak;

    always @(posedge i_clk) begin
        if (i_rst) begin
            pc <= RESET_ADDR;
            halted <= 1'b0;
        end else begin
            pc <= next_pc;
            halted <= halted | ebreak;
        end
    end
    assign o_imem_raddr = pc;

    // Decode: the instruction format and datapath controls are independent
    // from the state updates, which are gated below by active and trap.
    wire [5:0] format;
    wire use_rs1, use_rs2, alu_pc, alu_imm;
    wire [2:0] alu_op;
    wire alu_sub, alu_unsigned, alu_arith;
    wire [1:0] wb_sel;
    wire reg_write, load, store, branch, jal, jalr, illegal;
    decode decoder (
        .i_inst(inst), .o_format(format),
        .o_use_rs1(use_rs1), .o_use_rs2(use_rs2),
        .o_alu_pc(alu_pc), .o_alu_imm(alu_imm), .o_alu_op(alu_op),
        .o_alu_sub(alu_sub), .o_alu_unsigned(alu_unsigned),
        .o_alu_arith(alu_arith), .o_wb_sel(wb_sel),
        .o_reg_write(reg_write), .o_load(load), .o_store(store),
        .o_branch(branch), .o_jal(jal), .o_jalr(jalr),
        .o_ebreak(ebreak), .o_illegal(illegal)
    );
    wire [31:0] immediate;
    imm immediate_generator (
        .i_inst(inst), .i_format(format), .o_immediate(immediate)
    );
    wire [4:0] rs1_addr = use_rs1 ? inst[19:15] : 5'd0;
    wire [4:0] rs2_addr = use_rs2 ? inst[24:20] : 5'd0;
    wire [4:0] rd_addr = inst[11:7];
    wire [31:0] rs1_data, rs2_data, wb_data;
    wire rd_wen;
    rf #(.BYPASS_EN(0)) registers (
        .i_clk(i_clk), .i_rst(i_rst),
        .i_rs1_raddr(rs1_addr), .o_rs1_rdata(rs1_data),
        .i_rs2_raddr(rs2_addr), .o_rs2_rdata(rs2_data),
        .i_rd_wen(rd_wen), .i_rd_waddr(rd_addr), .i_rd_wdata(wb_data)
    );

    // Execute. Branches compare the unmodified register operands in the
    // ALU, while a separate adder computes the PC-relative target.
    wire [31:0] operand_a = alu_pc ? pc : rs1_data;
    wire [31:0] operand_b = alu_imm ? immediate : rs2_data;
    wire [31:0] alu_result;
    wire equal, less;
    alu execution_unit (
        .i_opsel(alu_op), .i_sub(alu_sub), .i_unsigned(alu_unsigned),
        .i_arith(alu_arith), .i_op1(operand_a), .i_op2(operand_b),
        .o_result(alu_result), .o_eq(equal), .o_slt(less)
    );
    wire branch_condition = (inst[14:12] == 3'b000) ? equal :
                             (inst[14:12] == 3'b001) ? ~equal :
                             (inst[14:12] == 3'b100) ? less :
                             (inst[14:12] == 3'b101) ? ~less :
                             (inst[14:12] == 3'b110) ? less :
                             (inst[14:12] == 3'b111) ? ~less : 1'b0;
    wire redirect = jal | jalr | (branch & branch_condition);
    wire [31:0] pc_target = pc + immediate;
    wire [31:0] target = jalr ? {alu_result[31:1], 1'b0} : pc_target;
    // A not-taken branch must not trap on an unused misaligned target.
    wire bad_target = redirect & (target[1:0] != 2'b00);

    // Memory adapter: address alignment is separate from access legality.
    wire [31:0] load_data;
    wire bad_data_alignment;
    lsu memory_adapter (
        .i_addr(alu_result), .i_store_data(rs2_data),
        .i_mem_data(i_dmem_rdata), .i_funct3(inst[14:12]),
        .o_addr(o_dmem_addr), .o_mask(o_dmem_mask),
        .o_store_data(o_dmem_wdata), .o_load_data(load_data),
        .o_misaligned(bad_data_alignment)
    );
    wire trap = illegal | bad_target | ((load | store) & bad_data_alignment) |
                (pc[1:0] != 2'b00);
    assign o_dmem_ren = active & load & ~trap;
    assign o_dmem_wen = active & store & ~trap;

    // Writeback and next PC. With no privileged trap-handler interface,
    // a trapping instruction reports the trap, has no side effects, and
    // continues at PC+4. EBREAK instead holds the PC and latches halt.
    assign wb_data = (wb_sel == 2'b01) ? load_data :
                     (wb_sel == 2'b10) ? pc4 :
                     (wb_sel == 2'b11) ? immediate : alu_result;
    assign rd_wen = active & reg_write & ~trap & (rd_addr != 5'd0);
    assign next_pc = (halted | ebreak) ? pc :
                     trap ? pc4 : redirect ? target : pc4;

    // Observe the same instruction whose effects commit at this edge.
    assign o_retire_valid = active;
    assign o_retire_inst = inst;
    assign o_retire_trap = active & trap;
    assign o_retire_halt = active & ebreak;
    assign o_retire_rs1_raddr = rs1_addr;
    assign o_retire_rs2_raddr = rs2_addr;
    assign o_retire_rs1_rdata = rs1_data;
    assign o_retire_rs2_rdata = rs2_data;
    assign o_retire_rd_waddr = rd_wen ? rd_addr : 5'd0;
    assign o_retire_rd_wdata = wb_data;
    assign o_retire_pc = pc;
    assign o_retire_next_pc = next_pc;
endmodule

`default_nettype wire
