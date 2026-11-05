`default_nettype none

// The arithmetic logic unit (ALU) is responsible for performing the core
// calculations of the processor. It takes two 32-bit operands and outputs
// a 32 bit result based on the selection operation - addition, comparison,
// shift, or logical operation. This ALU is a purely combinational block, so
// you should not attempt to add any registers or pipeline it.
module alu (
    // NOTE: Both 3'b010 and 3'b011 are used for set less than operations and
    // your implementation should output the same result for both codes. The
    // reason for this will become clear in project 3.
    //
    // Major operation selection.
    // 3'b000: addition/subtraction if `i_sub` asserted
    // 3'b001: shift left logical
    // 3'b010,
    // 3'b011: set less than/unsigned if `i_unsigned` asserted
    // 3'b100: exclusive or
    // 3'b101: shift right logical/arithmetic if `i_arith` asserted
    // 3'b110: or
    // 3'b111: and
    input  wire [ 2:0] i_opsel,
    // When asserted, addition operations should subtract instead.
    // This is only used for `i_opsel == 3'b000` (addition/subtraction).
    input  wire        i_sub,
    // When asserted, comparison operations should be treated as unsigned.
    // This is used for branch comparisons and set less than unsigned. For
    // branch operations, the ALU result is not used, only the comparison
    // results.
    input  wire        i_unsigned,
    // When asserted, right shifts should be treated as arithmetic instead of
    // logical. This is only used for `i_opsel == 3'b101` (shift right).
    input  wire        i_arith,
    // First 32-bit input operand.
    input  wire [31:0] i_op1,
    // Second 32-bit input operand.
    input  wire [31:0] i_op2,
    // 32-bit output result. Any carry out should be ignored.
    output wire [31:0] o_result,
    // Equality result. This is used externally to determine if a branch
    // should be taken.
    output wire        o_eq,
    // Set less than result. This is used externally to determine if a branch
    // should be taken.
    output wire        o_slt
);
    // Compute candidate results in parallel; the mux below selects one.
    // Keeping only 32 output bits discards carry/overflow beyond bit 31.
    wire [31:0] result_add = i_sub ? (i_op1 - i_op2) : (i_op1 + i_op2);
    wire [31:0] result_xor = i_op1 ^ i_op2;
    wire [31:0] result_or  = i_op1 | i_op2;
    wire [31:0] result_and = i_op1 & i_op2;

    // Build a variable shift from optional shifts of 1, 2, 4, 8, and 16 bits.
    // For example, shift by 5 enables the 1-bit and 4-bit steps.
    // RV32I uses only the low five bits of the shift amount (0 through 31).
    // These are combinational steps, not separate clock cycles.
    wire [31:0] sll_s0 = i_op2[0] ? {i_op1[30:0], 1'b0}   : i_op1;
    wire [31:0] sll_s1 = i_op2[1] ? {sll_s0[29:0], 2'b0}  : sll_s0;
    wire [31:0] sll_s2 = i_op2[2] ? {sll_s1[27:0], 4'b0}  : sll_s1;
    wire [31:0] sll_s3 = i_op2[3] ? {sll_s2[23:0], 8'b0}  : sll_s2;
    wire [31:0] sll_s4 = i_op2[4] ? {sll_s3[15:0], 16'b0} : sll_s3;
    wire [31:0] result_sll = sll_s4;

    // The right shifter uses the same five-step idea. Logical right shifts
    // insert zeros; arithmetic right shifts copy the original sign bit.
    wire shr_fill = i_arith & i_op1[31];
    wire [31:0] shr_s0 = i_op2[0] ? {{1{shr_fill}},  i_op1[31:1]}  : i_op1;
    wire [31:0] shr_s1 = i_op2[1] ? {{2{shr_fill}},  shr_s0[31:2]} : shr_s0;
    wire [31:0] shr_s2 = i_op2[2] ? {{4{shr_fill}},  shr_s1[31:4]} : shr_s1;
    wire [31:0] shr_s3 = i_op2[3] ? {{8{shr_fill}},  shr_s2[31:8]} : shr_s2;
    wire [31:0] shr_s4 = i_op2[4] ? {{16{shr_fill}}, shr_s3[31:16]} : shr_s3;
    wire [31:0] result_shr = shr_s4;

    // For signed comparison, differing signs mean the negative value is less.
    // If signs match, comparing the unsigned bit patterns gives the right order.
    wire signed_lt   = (i_op1[31] ^ i_op2[31]) ? i_op1[31] : (i_op1 < i_op2);
    wire unsigned_lt = (i_op1 < i_op2);
    wire slt_result  = i_unsigned ? unsigned_lt : signed_lt;
    // SLT/SLTU write the number 0 or 1, so pad the comparison bit with zeros.
    wire [31:0] result_slt = {31'b0, slt_result};

    // Select which candidate becomes the instruction's ALU result.
    assign o_result = (i_opsel == 3'b000) ? result_add :
                      (i_opsel == 3'b001) ? result_sll :
                      (i_opsel == 3'b100) ? result_xor :
                      (i_opsel == 3'b101) ? result_shr :
                      (i_opsel == 3'b110) ? result_or  :
                      (i_opsel == 3'b111) ? result_and :
                      result_slt;

    // Comparisons are available independently of the selected result.
    // hart.v uses them to decide whether a branch should be taken.
    assign o_eq  = (i_op1 == i_op2);
    assign o_slt = slt_result;
endmodule

`default_nettype wire
