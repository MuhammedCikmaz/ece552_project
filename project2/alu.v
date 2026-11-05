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
    // b ranch operations, the ALU result is not used, only the comparison
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
    // helper signal
    wire [4:0] shamt = i_op2[4:0];

    // comparison: unsigned, signed, then pick one
    wire ult = (i_op1 < i_op2);
    wire lt = (i_op1[31] != i_op2[31]) ? i_op1[31] : ult;
    wire slt = i_unsigned ? ult : lt;

    // one wire per operation
    wire [31:0] addsub_result = i_sub ? (i_op1 - i_op2) : (i_op1 + i_op2);
    wire [31:0] slt_result = {31'b0, slt};
    wire [31:0] xor_result = i_op1 ^ i_op2;

    // left shift
    wire [31:0] sl16 = shamt[4] ? {i_op1[15:0], 16'b0} : i_op1;
    wire [31:0] sl8 = shamt[3] ? {sl16[23:0], 8'b0} : sl16;
    wire [31:0] sl4 = shamt[2] ? {sl8[27:0], 4'b0} : sl8;
    wire [31:0] sl2 = shamt[1] ? {sl4[29:0], 2'b0} : sl4;
    wire [31:0] sll_result = shamt[0] ? {sl2[30:0], 1'b0} : sl2;

    // right shift
    wire fill = i_arith & i_op1[31];
    wire [31:0] sr16 = shamt[4] ? {{16{fill}}, i_op1[31:16]} : i_op1;
    wire [31:0] sr8 = shamt[3] ? {{8{fill}}, sr16[31:8]} : sr16;
    wire [31:0] sr4 = shamt[2] ? {{4{fill}}, sr8[31:4]} : sr8;
    wire [31:0] sr2 = shamt[1] ? {{2{fill}}, sr4[31:2]} : sr4;
    wire [31:0] shr_result = shamt[0] ? {fill, sr2[31:1]} : sr2;

    wire [31:0] or_result = i_op1 | i_op2;
    wire [31:0] and_result = i_op1 & i_op2;

    // select which one is correct
    assign o_result = (i_opsel == 3'b000) ? addsub_result :
                      (i_opsel == 3'b001) ? sll_result :
                      (i_opsel == 3'b010) ? slt_result :
                      (i_opsel == 3'b011) ? slt_result :
                      (i_opsel == 3'b100) ? xor_result :
                      (i_opsel == 3'b101) ? shr_result :
                      (i_opsel == 3'b110) ? or_result :
                                            and_result; // 3'b111

    // branch outputs
    assign o_eq = (i_op1 == i_op2);
    assign o_slt = slt;

endmodule

`default_nettype wire