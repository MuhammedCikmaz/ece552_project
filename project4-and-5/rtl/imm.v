`default_nettype none

// The immediate generator is responsible for decoding the 32-bit sign-extended
// immediate from the incoming instruction word. It is a purely combinational
// block that is expected to be embedded in the instruction decoder.
module imm (
    // Input instruction word. This is used to extract the relevant immediate
    // bits and assemble them into the final immediate.
    input  wire [31:0] i_inst,
    // Instruction format, determined by the instruction decoder based on the
    // opcode. This is one-hot encoded according to the following format:
    // [0] R-type
    // [1] I-type
    // [2] S-type
    // [3] B-type
    // [4] U-type
    // [5] J-type
    input  wire [ 5:0] i_format,
    // Output 32-bit sign-extended immediate.
    // NOTE: Because the R-type format does not have an immediate, the output
    // immediate can be treated as a don't-care under this case. It is included
    // for completeness.
    output wire [31:0] o_immediate
);
    // Reassemble the immediate bits, which occupy different positions in
    // different instruction formats. {a, b} joins bit fields; {N{bit}} repeats
    // a bit N times. Repeating the sign bit preserves negative immediates.
    // R-type has no immediate, so its unused result is explicitly unknown (x).
    wire [31:0] imm_r = {{32{1'bx}}};
    // I: arithmetic constants, load offsets, and JALR offsets.
    wire [31:0] imm_i = {{21{i_inst[31]}}, i_inst[30:20]};
    // S: store offsets are split across two instruction fields.
    wire [31:0] imm_s = {{21{i_inst[31]}}, i_inst[30:25], i_inst[11:7]};
    // B: branch offsets have an implicit low zero, so they are multiples of 2.
    wire [31:0] imm_b = {{20{i_inst[31]}}, i_inst[7], i_inst[30:25], i_inst[11:8], 1'b0};
    // U: LUI/AUIPC place the encoded constant in the upper 20 bits.
    wire [31:0] imm_u = {i_inst[31:12], 12'b0};
    // J: JAL offsets also have an implicit low zero and rearranged bit fields.
    wire [31:0] imm_j = {{11{i_inst[31]}}, 
                        i_inst[31],        
                        i_inst[19:12],   
                        i_inst[20],        
                        i_inst[30:21],    
                        1'b0};             

    // Select the format requested by hart.v; no active format returns zero.
    assign o_immediate = i_format[0] ? imm_r :
                         i_format[1] ? imm_i :
                         i_format[2] ? imm_s :
                         i_format[3] ? imm_b :
                         i_format[4] ? imm_u :
                         i_format[5] ? imm_j :
                         32'b0;
endmodule

`default_nettype wire
