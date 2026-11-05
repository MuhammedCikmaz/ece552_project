`timescale 1ns/1ps

// Verification only: never submit this file as processor RTL.
module differential_tb;
    parameter RESET_ADDR = 32'd0;
    reg clk = 0;
    reg rst = 1;
    wire [31:0] imem_addr, dmem_addr, dmem_wdata;
    wire [31:0] imem_data, dmem_data;
    wire dmem_ren, dmem_wen;
    wire [3:0] dmem_mask;
    wire valid, trap, halt;
    wire [31:0] inst, rs1_data, rs2_data, rd_data, pc, next_pc;
    wire [4:0] rs1, rs2, rd;
    reg [7:0] imem [0:65535];
    reg [7:0] dmem [0:65535];
    reg [1023:0] program_path;
    integer n, cycles, restarts;
    reg [31:0] halt_pc;

    hart #(.RESET_ADDR(RESET_ADDR)) dut (
        .i_clk(clk), .i_rst(rst), .o_imem_raddr(imem_addr), .i_imem_rdata(imem_data),
        .o_dmem_addr(dmem_addr), .o_dmem_ren(dmem_ren), .o_dmem_wen(dmem_wen),
        .o_dmem_wdata(dmem_wdata), .o_dmem_mask(dmem_mask), .i_dmem_rdata(dmem_data),
        .o_retire_valid(valid), .o_retire_inst(inst), .o_retire_trap(trap),
        .o_retire_halt(halt), .o_retire_rs1_raddr(rs1), .o_retire_rs2_raddr(rs2),
        .o_retire_rs1_rdata(rs1_data), .o_retire_rs2_rdata(rs2_data),
        .o_retire_rd_waddr(rd), .o_retire_rd_wdata(rd_data),
        .o_retire_pc(pc), .o_retire_next_pc(next_pc)
    );

    always #5 clk = ~clk;
    assign imem_data = {imem[imem_addr+3], imem[imem_addr+2], imem[imem_addr+1], imem[imem_addr]};
    // Unselected lanes are deliberately unknown, matching the supplied tb.
    assign dmem_data[7:0] = dmem_ren && dmem_mask[0] ? dmem[dmem_addr] : 8'hxx;
    assign dmem_data[15:8] = dmem_ren && dmem_mask[1] ? dmem[dmem_addr+1] : 8'hxx;
    assign dmem_data[23:16] = dmem_ren && dmem_mask[2] ? dmem[dmem_addr+2] : 8'hxx;
    assign dmem_data[31:24] = dmem_ren && dmem_mask[3] ? dmem[dmem_addr+3] : 8'hxx;
    always @(posedge clk) begin
        if (dmem_wen && dmem_mask[0]) dmem[dmem_addr] <= dmem_wdata[7:0];
        if (dmem_wen && dmem_mask[1]) dmem[dmem_addr+1] <= dmem_wdata[15:8];
        if (dmem_wen && dmem_mask[2]) dmem[dmem_addr+2] <= dmem_wdata[23:16];
        if (dmem_wen && dmem_mask[3]) dmem[dmem_addr+3] <= dmem_wdata[31:24];
    end
    initial begin
        if (!$value$plusargs("program=%s", program_path)) $fatal(1, "Missing program");
        for (n=0; n<65536; n=n+1) begin
            imem[n] = 0;
            dmem[n] = (n*37+11) & 255;
        end
        $readmemh(program_path, imem);
        restarts = $test$plusargs("restart");
        repeat (2) @(negedge clk);
        if (imem_addr !== RESET_ADDR || valid !== 0 || dmem_wen !== 0 || dmem_ren !== 0)
            $fatal(1, "Reset state or side effects incorrect");
        rst = 0;
        cycles = 0;
        forever begin
            @(posedge clk);
            cycles = cycles+1;
            if (valid !== 1'b1) $fatal(1, "Expected one retirement every active cycle");
            if (dmem_ren && dmem_wen) $fatal(1, "Simultaneous load and store");
            $display("RET %08h %08h %02h %08h %02h %08h %02h %08h %08h %01h %01h %01h %01h %08h %01h %08h",
                pc, inst, rs1, rs1_data, rs2, rs2_data, rd, rd_data, next_pc,
                trap, halt, dmem_ren, dmem_wen, dmem_addr, dmem_mask, dmem_wdata);
            if (halt) begin
                halt_pc = pc;
                repeat (3) begin
                    @(negedge clk);
                    if (valid !== 0 || dmem_wen !== 0 || dmem_ren !== 0 || imem_addr !== halt_pc)
                        $fatal(1, "Processor did not remain halted");
                end
                if (restarts != 0) begin
                    rst = 1;
                    repeat (2) @(negedge clk);
                    if (imem_addr !== RESET_ADDR || valid !== 0) $fatal(1, "Restart reset failed");
                    rst = 0;
                    restarts = 0;
                    $display("RESTART");
                end else begin
                    $display("HALT_OK");
                    $finish;
                end
            end
            if (cycles > 100000) $fatal(1, "Execution timeout");
        end
    end
endmodule
