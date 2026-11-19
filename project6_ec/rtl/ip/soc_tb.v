// Simulation testbench for the SoC.
//
// SIMULATION ONLY -- do not add this file to the Quartus project.
//
// Instantiates soc_core (the same module the board top level uses) and drives
// the switches and buttons the way a person would, then checks what appears on
// the LEDs and displays. Running a program here before flashing it is much
// faster than waiting for a Quartus compile to find out it does nothing.
//
//   iverilog -g2005 -o soc_tb.out -s soc_tb *.v <your rtl>/*.v
//   vvp soc_tb.out +PROG=cpi +ILAT=4 +DLAT=4 +IVL=2
//
// cpi is the only program in this lab, so +PROG only selects which set of
// checks to run. The memory image comes from program.mem, so build it first.
//
// +ILAT, +DLAT and +IVL set the instruction memory latency, the data memory
// latency and the initiation interval, exactly the way the switches do on the
// board: they are driven onto SW[7:0] and sampled while reset is held.
//
// Sweeping them here is the cheap way to find out whether your processor
// really reads mem_ready and mem_valid rather than assuming a fixed latency --
// if it only works at +ILAT=4, it is going to fail on the board and it would
// have failed the Gradescope tests too.
//
// The two latencies are independent. +ILAT=8 +DLAT=1 and +ILAT=1 +DLAT=8 are
// the two configurations the demo is built around, and a processor that
// handles one but not the other has a real bug.
//
// The CPI is checked but deliberately never printed. Students commit to
// predictions before the demo and see their CPI for the first time on the
// board. This simulation runs the same design cycle for cycle, so it gives
// the board's exact numbers, and printing them would give the answer away.
// The CPI and LED checks still report a failure, with the values they saw,
// when one goes wrong; they just say nothing when they pass.

`timescale 1ns / 1ps
`default_nettype none

module soc_tb ();

    // ------------------------------------------------------------ stimulus
    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [ 9:0] sw  = 10'd0;
    reg  [ 3:0] key_n = 4'hF;           // active low: all released

    wire [ 9:0] ledr;
    wire [23:0] hex_val;
    wire [ 5:0] hex_en;
    wire        retire_valid, retire_halt, retire_trap;
    wire [31:0] retire_pc, retire_inst;

    integer errors = 0;

    integer want_ilat = 4;
    integer want_dlat = 4;
    integer want_ivl  = 2;

    soc_core #(
        .IMEM_WORDS  (1024),
        .DMEM_WORDS  (1024),
        .MAX_LATENCY (8),
        .INIT_FILE   ("program.mem")
    ) dut (
        .i_clk          (clk),
        .i_rst          (rst),
        .i_sw           (sw),
        .i_key_n        (key_n),
        .o_ledr         (ledr),
        .o_hex_val      (hex_val),
        .o_hex_en       (hex_en),
        .o_retire_valid (retire_valid),
        .o_retire_halt  (retire_halt),
        .o_retire_trap  (retire_trap),
        .o_retire_pc    (retire_pc),
        .o_retire_inst  (retire_inst)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        // A trap should never happen with these programs on a correct
        // processor. If one does, say so loudly and stop -- it means the
        // processor hit an illegal instruction or a misaligned access.
        if (retire_valid && retire_trap) begin
            $display("TRAP at pc=%08h inst=%08h", retire_pc, retire_inst);
            errors = errors + 1;
            $finish;
        end
    end

    // --------------------------------------------------------------- helpers
    task run_cycles(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    task press(input integer idx, input integer hold);
        begin
            key_n[idx] = 1'b0;
            run_cycles(hold);
            key_n[idx] = 1'b1;
            run_cycles(hold);
        end
    endtask

    task check(input [255:0] what, input [31:0] got, input [31:0] want);
        begin
            if (got !== want) begin
                $display("  FAIL %0s: got %08h, want %08h", what, got, want);
                errors = errors + 1;
            end else begin
                $display("  ok   %0s = %08h", what, got);
            end
        end
    endtask

    // Like check, but silent when it passes. Used for checks whose passing
    // value would tell a student what the board is going to show.
    task check_quiet(input [255:0] what, input [31:0] got, input [31:0] want);
        begin
            if (got !== want) begin
                $display("  FAIL %0s: got %08h, want %08h", what, got, want);
                errors = errors + 1;
            end
        end
    endtask

    // Checks the current CPI reading on hex_val, for either workload. Silent
    // when it passes -- see the top of this file for why the CPI is never
    // printed.
    task check_cpi_display(input [255:0] label);
        begin
            if (hex_val[15:12] > 4'd9 || hex_val[11:8] > 4'd9 ||
                hex_val[7:4] > 4'd9 || hex_val[3:0] > 4'd9) begin
                $display("  FAIL %0s cpi digits not decimal: %04h", label, hex_val[15:0]);
                errors = errors + 1;
            end

            if (hex_val[15:0] == 16'h0000) begin
                $display("  FAIL %0s cpi reads 00.00 -- no measurement completed", label);
                errors = errors + 1;
            end
        end
    endtask

    // Bring the memories up with a given latency and interval, the same way
    // the board does: drive the switches, hold reset, let go.
    task set_mem_cfg(input integer ilat, input integer dlat,
                     input integer ivl);
        begin
            sw      = 10'd0;
            sw[2:0] = ilat - 1;
            sw[5:3] = dlat - 1;
            sw[7:6] = ivl - 1;
            rst = 1'b1;
            run_cycles(8);
            rst = 1'b0;
            sw  = 10'd0;        // the switches belong to the program now
            run_cycles(4);
        end
    endtask

    // ------------------------------------------------------------------ main
    reg [63:0] prog;

    initial begin
        if (!$value$plusargs("PROG=%s", prog))
            prog = "cpi";
        if (!$value$plusargs("ILAT=%d", want_ilat))
            want_ilat = 4;
        if (!$value$plusargs("DLAT=%d", want_dlat))
            want_dlat = 4;
        if (!$value$plusargs("IVL=%d", want_ivl))
            want_ivl = 2;

        $display("=== soc_tb: %0s   imem latency=%0d  dmem latency=%0d  interval=%0d ===",
                 prog, want_ilat, want_dlat, want_ivl);

        set_mem_cfg(want_ilat, want_dlat, want_ivl);
        run_cycles(20);

        case (prog)
        "cpi": begin
            // One full measurement takes a few thousand instructions, so give
            // it room to finish and publish a result.
            run_cycles(300000);

            // HEX5 and HEX4 are read back from MEM_CFG, so they prove the
            // switch sampling and the MEM_CFG register agree with what this
            // testbench asked for -- including that the two latencies did not
            // get crossed over or tied together somewhere.
            check("imem latency digit", {28'd0, hex_val[23:20]}, want_ilat);
            check("dmem latency digit", {28'd0, hex_val[19:16]}, want_dlat);
            check("hex_en",             {26'd0, hex_en},         32'h3F);

            // LEDR[3:0] carries the initiation interval in unary: N lit
            // means N. LEDR[9] carries the workload bit, which cpi.c moved
            // off HEX3 to make room for a fourth CPI digit -- it should read
            // 0 (ALU workload) before the KEY0 press below.
            check_quiet("interval+workload on ledr", {22'd0, ledr},
                        ((32'd1 << want_ivl) - 32'd1));

            check_cpi_display("workload0");

            // KEY0 switches to the load/store workload. cpi.c looks at the
            // latch once per measurement and writes the displays before it,
            // so allow two more measurements for the change to appear.
            press(0, 200);
            run_cycles(600000);
            check_quiet("workload on ledr after KEY0", {22'd0, ledr[9]}, 32'd1);

            check_cpi_display("workload1");
        end

        default: begin
            $display("  unknown program %0s", prog);
            errors = errors + 1;
        end
        endcase

        $display("=== %0d error(s) ===", errors);
        if (errors != 0)
            $fatal(1, "FAILED");
        $finish;
    end

    // Safety net: these programs never halt on their own.
    initial begin
        #40_000_000;
        $display("timeout");
        $fatal(1, "TIMEOUT");
    end

endmodule

`default_nettype wire
