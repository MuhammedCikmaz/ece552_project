// Self-test for the memory subsystem. No processor involved.
//
// SIMULATION ONLY -- do not add this file to the Quartus project.
//
// soc_tb.v tests the whole SoC, which means it can only tell you something
// once a working hart is wired in. This testbench instead drives imem, dbus
// and mmio directly, so it answers a narrower question: do the board's
// memories actually honour the Project 6 contract, at every latency and
// interval the switches can select?
//
//   iverilog -g2005 -o mem_tb.out -s mem_tb ip/mem_pipe.v ip/imem.v \
//            ip/dbus.v ip/mmio.v ip/mem_tb.v
//   vvp mem_tb.out
//
// It needs program.mem present, because imem is initialised from it, but it
// does not care what program that is.
//
// What it checks, for every latency 1..8 crossed with every interval 1..4:
//
//   * a response arrives exactly `latency` cycles after the request was
//     accepted -- not earlier, not later
//   * o_ready stays low for exactly `interval`-1 cycles after an accepted
//     request, so a new one can start every `interval` cycles
//   * with several requests in flight at once, responses come back in order
//   * data memory reads return what was written, including byte-masked writes
//   * peripheral reads and writes work through the same handshake, and a
//     peripheral access immediately after a memory access returns the
//     peripheral's data rather than the memory's (that is the select
//     pipeline in dbus.v lining up with the data)
//
// If this passes and your processor still does not work on the board, the
// problem is in your processor's handling of ready/valid, not in the wrapper.
//
// Note on style: every task here drives signals, then waits for a clock edge,
// then waits a further #1 before looking at anything. Without that settling
// delay a testbench can read a registered output in the same simulation
// instant the clock updated it and see the old value -- which looks exactly
// like a latency that is one cycle too long. The delay costs nothing and
// removes the whole class of problem.

`timescale 1ns / 1ps
`default_nettype none

module mem_tb ();

    localparam MAXL = 8;
    localparam MAXI = 4;

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg [3:0] cfg_lat = 4'd4;
    reg [3:0] cfg_ivl = 4'd2;

    integer errors = 0;

    always #5 clk = ~clk;

    // Advance one cycle and settle, so every sample afterwards is stable.
    task step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    // ------------------------------------------------------------------ imem
    wire        im_ready, im_valid;
    reg  [31:0] im_raddr;
    reg         im_ren;
    wire [31:0] im_rdata;

    imem #(
        .WORDS       (1024),
        .INIT_FILE   ("program.mem"),
        .MAX_LATENCY (MAXL)
    ) u_imem (
        .i_clk          (clk),
        .i_rst          (rst),
        .i_cfg_latency  (cfg_lat),
        .i_cfg_interval (cfg_ivl),
        .o_ready        (im_ready),
        .i_raddr        (im_raddr),
        .i_ren          (im_ren),
        .o_valid        (im_valid),
        .o_rdata        (im_rdata)
    );

    // ------------------------------------------------------------ dbus + mmio
    wire        db_ready, db_valid;
    reg  [31:0] db_addr, db_wdata;
    reg         db_ren, db_wen;
    reg  [ 3:0] db_mask;
    wire [31:0] db_rdata;

    wire [31:0] mmio_addr, mmio_wdata, mmio_rdata;
    wire        mmio_ren, mmio_wen;

    dbus #(
        .WORDS       (1024),
        .INIT_FILE0  ("program.lane0.mem"),
        .INIT_FILE1  ("program.lane1.mem"),
        .INIT_FILE2  ("program.lane2.mem"),
        .INIT_FILE3  ("program.lane3.mem"),
        .MAX_LATENCY (MAXL)
    ) u_dbus (
        .i_clk          (clk),
        .i_rst          (rst),
        .i_cfg_latency  (cfg_lat),
        .i_cfg_interval (cfg_ivl),
        .o_ready        (db_ready),
        .i_addr         (db_addr),
        .i_ren          (db_ren),
        .i_wen          (db_wen),
        .i_wdata        (db_wdata),
        .i_mask         (db_mask),
        .o_valid        (db_valid),
        .o_rdata        (db_rdata),
        .o_mmio_addr    (mmio_addr),
        .o_mmio_ren     (mmio_ren),
        .o_mmio_wen     (mmio_wen),
        .o_mmio_wdata   (mmio_wdata),
        .i_mmio_rdata   (mmio_rdata)
    );

    mmio u_mmio (
        .i_clk          (clk),
        .i_rst          (rst),
        .i_addr         (mmio_addr),
        .i_ren          (mmio_ren),
        .i_wen          (mmio_wen),
        .i_wdata        (mmio_wdata),
        .o_rdata        (mmio_rdata),
        .i_cfg_ilatency (cfg_lat),
        .i_cfg_dlatency (cfg_lat),
        .i_cfg_interval (cfg_ivl),
        .i_sw_raw       (10'h2AA),
        .i_key_raw_n    (4'hF),
        .i_retire       (1'b0),
        .o_ledr         (),
        .o_hex_val      (),
        .o_hex_en       ()
    );

    // --------------------------------------------------------------- helpers
    task expect(input [255:0] what, input [31:0] got, input [31:0] want);
        begin
            if (got !== want) begin
                $display("  FAIL %0s: got %08h, want %08h  (latency=%0d interval=%0d)",
                         what, got, want, cfg_lat, cfg_ivl);
                errors = errors + 1;
            end
        end
    endtask

    task expect_int(input [255:0] what, input integer got, input integer want);
        begin
            if (got !== want) begin
                $display("  FAIL %0s: got %0d, want %0d  (latency=%0d interval=%0d)",
                         what, got, want, cfg_lat, cfg_ivl);
                errors = errors + 1;
            end
        end
    endtask

    task reconfigure(input integer lat, input integer ivl);
        begin
            im_ren  = 1'b0;
            db_ren  = 1'b0;
            db_wen  = 1'b0;
            cfg_lat = lat[3:0];
            cfg_ivl = ivl[3:0];
            rst     = 1'b1;
            step; step;
            rst     = 1'b0;
            step;
        end
    endtask

    // The expected contents of imem at a byte address, read straight out of
    // the model's own array -- this checks the plumbing, not the file.
    function [31:0] mem_word(input [31:0] byte_addr);
        mem_word = u_imem.mem[byte_addr[11:2]];
    endfunction

    // ------------------------------------------------- one timed imem fetch
    // Returns the data and the measured response latency in cycles, or -1 if
    // no response ever arrived.
    task imem_read_timed(input  [31:0] addr,
                         output [31:0] data,
                         output integer meas_lat);
        integer n;
        begin
            while (!im_ready) step;

            im_raddr = addr;
            im_ren   = 1'b1;
            step;                       // the edge just taken ends cycle 0
            im_ren   = 1'b0;

            // We are now settled inside cycle 1.
            n = 1;
            while (!im_valid && n <= MAXL + 4) begin
                step;
                n = n + 1;
            end

            meas_lat = (n > MAXL + 4) ? -1 : n;
            data     = im_rdata;
            step;
        end
    endtask

    // ------------------------------------------------ the initiation interval
    // Counted on its own rather than alongside the latency measurement above.
    // When the interval is longer than the latency the response arrives while
    // o_ready is still low, so anything that stops counting at the response
    // reports an interval that is too short -- the interval is a property of
    // the request port and has to be measured there.
    task imem_interval_test(output integer meas_low);
        integer n;
        begin
            while (!im_ready) step;

            im_raddr = 32'h00000000;
            im_ren   = 1'b1;
            step;
            im_ren   = 1'b0;

            meas_low = 0;
            n        = 0;
            while (!im_ready && n < MAXL + MAXI + 4) begin
                meas_low = meas_low + 1;
                step;
                n        = n + 1;
            end

            // Let the outstanding response retire before the next test.
            repeat (MAXL + 2) step;
        end
    endtask

    // -------------------------------------------------------- one dbus access
    // For a read, blocks until the response and checks its latency. For a
    // write, returns once the write has had time to reach the storage.
    task dbus_req(input [31:0] addr, input ren, input wen,
                  input [3:0] mask, input [31:0] wdata, output [31:0] rdata);
        integer n;
        begin
            while (!db_ready) step;

            db_addr  = addr;
            db_ren   = ren;
            db_wen   = wen;
            db_mask  = mask;
            db_wdata = wdata;
            step;
            db_ren   = 1'b0;
            db_wen   = 1'b0;

            rdata = 32'd0;
            if (ren) begin
                n = 1;
                while (!db_valid && n <= MAXL + 4) begin
                    step;
                    n = n + 1;
                end
                if (n > MAXL + 4) begin
                    $display("  FAIL dbus valid never arrived  (latency=%0d interval=%0d)",
                             cfg_lat, cfg_ivl);
                    errors = errors + 1;
                end else begin
                    expect_int("dbus latency", n, cfg_lat);
                end
                rdata = db_rdata;
            end
            // Let a write drain all the way into the storage before anyone
            // tries to read it back.
            if (wen)
                repeat (MAXL + 2) step;
        end
    endtask

    // --------------------------------------------------- back-to-back ordering
    // Issue three imem reads as fast as o_ready allows, collecting responses
    // as they arrive. With latency > interval these really are in flight
    // together, which is the case that catches a pipeline that reorders.
    task imem_ordering_test;
        integer i, got, t;
        reg [31:0] seen [0:2];
        begin
            i   = 0;
            got = 0;

            for (t = 0; t < 128 && got < 3; t = t + 1) begin
                // Drive this cycle's request, based on signals sampled while
                // settled inside the previous cycle.
                if (i < 3 && im_ready) begin
                    im_raddr = 32'h40 + (i * 4);
                    im_ren   = 1'b1;
                    i        = i + 1;
                end else begin
                    im_ren   = 1'b0;
                end

                step;
                im_ren = 1'b0;

                if (im_valid) begin
                    seen[got] = im_rdata;
                    got       = got + 1;
                end
            end

            if (got != 3) begin
                $display("  FAIL imem ordering: only %0d of 3 responses  (latency=%0d interval=%0d)",
                         got, cfg_lat, cfg_ivl);
                errors = errors + 1;
            end else begin
                for (i = 0; i < 3; i = i + 1)
                    expect("imem ordering", seen[i], mem_word(32'h40 + (i * 4)));
            end
        end
    endtask

    // ------------------------------------------------------------------ main
    integer lat, ivl;
    integer m_lat, m_low;
    reg [31:0] d, d2;

    initial begin
        im_raddr = 32'd0; im_ren = 1'b0;
        db_addr  = 32'd0; db_ren = 1'b0; db_wen = 1'b0;
        db_mask  = 4'hF;  db_wdata = 32'd0;

        $display("=== mem_tb: memory subsystem self-test ===");

        for (lat = 1; lat <= MAXL; lat = lat + 1) begin
            for (ivl = 1; ivl <= MAXI; ivl = ivl + 1) begin
                reconfigure(lat, ivl);

                // --- instruction fetch: the data and the response latency
                imem_read_timed(32'h00000000, d, m_lat);
                expect("imem word 0", d, mem_word(32'h0));
                expect_int("imem latency", m_lat, lat);

                imem_read_timed(32'h00000010, d, m_lat);
                expect("imem word 4", d, mem_word(32'h10));
                expect_int("imem latency", m_lat, lat);

                // --- the initiation interval, measured at the request port
                imem_interval_test(m_low);
                expect_int("imem ready-low cycles", m_low, ivl - 1);

                // --- several fetches in flight at once, in order
                imem_ordering_test;

                // --- data memory: word write then read back
                dbus_req(32'h00000200, 1'b0, 1'b1, 4'hF, 32'hA5A5_1234, d);
                dbus_req(32'h00000200, 1'b1, 1'b0, 4'hF, 32'd0, d);
                expect("dmem word", d, 32'hA5A5_1234);

                // --- byte masks: overwrite two bytes, leave the others
                dbus_req(32'h00000200, 1'b0, 1'b1, 4'b0110, 32'hFFEE_DDCC, d);
                dbus_req(32'h00000200, 1'b1, 1'b0, 4'hF, 32'd0, d);
                expect("dmem byte mask", d, 32'hA5EE_DD34);

                // --- a second location, to catch an address stuck at one value
                dbus_req(32'h00000204, 1'b0, 1'b1, 4'hF, 32'h0BAD_F00D, d);
                dbus_req(32'h00000200, 1'b1, 1'b0, 4'hF, 32'd0, d);
                dbus_req(32'h00000204, 1'b1, 1'b0, 4'hF, 32'd0, d2);
                expect("dmem addr a", d,  32'hA5EE_DD34);
                expect("dmem addr b", d2, 32'h0BAD_F00D);

                // --- peripherals, through the same handshake
                dbus_req(32'h80000000, 1'b0, 1'b1, 4'hF, 32'h155, d);   // LEDR
                dbus_req(32'h80000000, 1'b1, 1'b0, 4'hF, 32'd0, d);
                expect("mmio ledr", d, 32'h155);

                dbus_req(32'h80000004, 1'b1, 1'b0, 4'hF, 32'd0, d);     // SW
                expect("mmio sw", d, 32'h2AA);

                dbus_req(32'h8000002C, 1'b1, 1'b0, 4'hF, 32'd0, d);     // MEM_CFG
                expect("mmio mem_cfg", d, {20'd0, cfg_ivl, cfg_lat, cfg_lat});

                // --- a memory access immediately followed by a peripheral one.
                // If dbus.v captured the select at the wrong time, this is
                // where it shows: the peripheral read would return the
                // memory's data, or the other way round.
                dbus_req(32'h00000200, 1'b1, 1'b0, 4'hF, 32'd0, d);
                dbus_req(32'h80000000, 1'b1, 1'b0, 4'hF, 32'd0, d2);
                expect("interleave mem",  d,  32'hA5EE_DD34);
                expect("interleave mmio", d2, 32'h155);

                dbus_req(32'h80000004, 1'b1, 1'b0, 4'hF, 32'd0, d);
                dbus_req(32'h00000204, 1'b1, 1'b0, 4'hF, 32'd0, d2);
                expect("interleave mmio first", d,  32'h2AA);
                expect("interleave mem second", d2, 32'h0BAD_F00D);
            end
        end

        $display("=== %0d error(s) over %0d configurations ===",
                 errors, MAXL * MAXI);
        if (errors != 0)
            $fatal(1, "FAILED");
        $display("all configurations passed");
        $finish;
    end

    initial begin
        #20_000_000;
        $display("timeout");
        $fatal(1, "TIMEOUT");
    end

endmodule

`default_nettype wire
