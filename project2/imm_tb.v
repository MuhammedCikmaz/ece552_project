// imm_tb.v
module imm_tb;
    reg  [31:0] i_inst;
    reg  [ 5:0] i_format;
    wire [31:0] o_immediate;

    imm uut (
        .i_inst(i_inst),
        .i_format(i_format),
        .o_immediate(o_immediate)
    );

    initial begin
        // I-type: addi x1, x0, 5     expect 00000005
        i_inst = 32'h00500093; i_format = 6'b000010; #1;
        $display("I +5   got %h", o_immediate);

        // I-type: addi x1, x0, -1    expect ffffffff
        i_inst = 32'hFFF00093; i_format = 6'b000010; #1;
        $display("I -1   got %h", o_immediate);

        // S-type: sw x2, 8(x1)       expect 00000008
        i_inst = 32'h0020A423; i_format = 6'b000100; #1;
        $display("S +8   got %h", o_immediate);

        // S-type: sw x2, -4(x1)      expect fffffffc
        i_inst = 32'hFE20AE23; i_format = 6'b000100; #1;
        $display("S -4   got %h", o_immediate);

        // B-type: beq x1, x2, +16    expect 00000010
        i_inst = 32'h00208863; i_format = 6'b001000; #1;
        $display("B +16  got %h", o_immediate);

        // B-type: beq x1, x2, -8     expect fffffff8
        i_inst = 32'hFE208CE3; i_format = 6'b001000; #1;
        $display("B -8   got %h", o_immediate);

        // U-type: lui x1, 0xABCDE    expect abcde000
        i_inst = 32'hABCDE0B7; i_format = 6'b010000; #1;
        $display("U hi   got %h", o_immediate);

        // U-type: lui x1, 0xF0000    expect f0000000
        i_inst = 32'hF00000B7; i_format = 6'b010000; #1;
        $display("U top  got %h", o_immediate);

        // J-type: jal x1, +16        expect 00000010
        i_inst = 32'h010000EF; i_format = 6'b100000; #1;
        $display("J +16  got %h", o_immediate);

        // J-type: jal x1, -8         expect fffffff8
        i_inst = 32'hFF9FF0EF; i_format = 6'b100000; #1;
        $display("J -8   got %h", o_immediate);

        $stop;
    end
endmodule
