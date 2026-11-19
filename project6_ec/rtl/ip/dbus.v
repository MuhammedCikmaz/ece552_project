// Data bus: 4 KB of block RAM plus the peripherals, behind one handshake.
`default_nettype none

module dbus #(
    parameter WORDS       = 1024,           // 4 KB
    // Four separate per-byte-lane images instead of one word-wide file --
    // see the storage section below for why.
    parameter INIT_FILE0  = "program.lane0.mem",
    parameter INIT_FILE1  = "program.lane1.mem",
    parameter INIT_FILE2  = "program.lane2.mem",
    parameter INIT_FILE3  = "program.lane3.mem",
    parameter MAX_LATENCY = 8
) (
    input  wire        i_clk,
    input  wire        i_rst,

    input  wire [ 3:0] i_cfg_latency,
    input  wire [ 3:0] i_cfg_interval,

    // Request/response port, wired straight to the hart's dmem interface.
    output wire        o_ready,
    input  wire [31:0] i_addr,
    input  wire        i_ren,
    input  wire        i_wen,
    input  wire [31:0] i_wdata,
    input  wire [ 3:0] i_mask,
    output wire        o_valid,
    output wire [31:0] o_rdata,

    // Peripheral side. mmio.v keeps the plain combinational-read interface it
    // has always had; this module is what gives it a handshake.
    output wire [31:0] o_mmio_addr,
    output wire        o_mmio_ren,
    output wire        o_mmio_wen,
    output wire [31:0] o_mmio_wdata,
    input  wire [31:0] i_mmio_rdata
);
    localparam AW = $clog2(WORDS);

    // ---------------------------------------------------------- the handshake
    wire [31:0] acc_addr;
    wire        acc_ren, acc_wen;
    wire [ 3:0] acc_mask;
    wire [31:0] acc_wdata;

    mem_pipe #(
        .MAX_LATENCY (MAX_LATENCY)
    ) u_pipe (
        .i_clk          (i_clk),
        .i_rst          (i_rst),
        .i_cfg_latency  (i_cfg_latency),
        .i_cfg_interval (i_cfg_interval),

        .o_ready        (o_ready),
        .i_addr         (i_addr),
        .i_ren          (i_ren),
        .i_wen          (i_wen),
        .i_mask         (i_mask),
        .i_wdata        (i_wdata),

        .o_acc_addr     (acc_addr),
        .o_acc_ren      (acc_ren),
        .o_acc_wen      (acc_wen),
        .o_acc_mask     (acc_mask),
        .o_acc_wdata    (acc_wdata),

        .o_valid        (o_valid),
        .o_wdone        (            )      // the hart does not need this
    );

    // --------------------------------------------------------------- the split
    wire acc_mmio = acc_addr[31];
    wire acc_ram  = ~acc_addr[31];

    assign o_mmio_addr  = acc_addr;
    assign o_mmio_ren   = acc_ren & acc_mmio;
    assign o_mmio_wen   = acc_wen & acc_mmio;
    assign o_mmio_wdata = acc_wdata;

    // ------------------------------------------------------------ the storage
    // Four separate byte-wide arrays, one per lane of the 32-bit word,
    // rather than one word-wide array with byte-enable writes.
    //
    // That word-wide-plus-byte-enable version is Intel's own documented
    // byte-enable RAM template
    //
    // Four lanes, each with its own plain (non-nested) write enable and its
    // own $readmemh, sidesteps it
    reg [7:0] mem0 [0:WORDS-1] /* synthesis ramstyle = "M10K, no_rw_check" */;
    reg [7:0] mem1 [0:WORDS-1] /* synthesis ramstyle = "M10K, no_rw_check" */;
    reg [7:0] mem2 [0:WORDS-1] /* synthesis ramstyle = "M10K, no_rw_check" */;
    reg [7:0] mem3 [0:WORDS-1] /* synthesis ramstyle = "M10K, no_rw_check" */;

    initial $readmemh(INIT_FILE0, mem0);
    initial $readmemh(INIT_FILE1, mem1);
    initial $readmemh(INIT_FILE2, mem2);
    initial $readmemh(INIT_FILE3, mem3);

    wire [AW-1:0] idx = acc_addr[AW+1:2];
    wire we_ram = acc_wen & acc_ram;

    always @(posedge i_clk) if (we_ram & acc_mask[0]) mem0[idx] <= acc_wdata[ 7: 0];
    always @(posedge i_clk) if (we_ram & acc_mask[1]) mem1[idx] <= acc_wdata[15: 8];
    always @(posedge i_clk) if (we_ram & acc_mask[2]) mem2[idx] <= acc_wdata[23:16];
    always @(posedge i_clk) if (we_ram & acc_mask[3]) mem3[idx] <= acc_wdata[31:24];

    reg [7:0] q0, q1, q2, q3;
    always @(posedge i_clk) q0 <= mem0[idx];
    always @(posedge i_clk) q1 <= mem1[idx];
    always @(posedge i_clk) q2 <= mem2[idx];
    always @(posedge i_clk) q3 <= mem3[idx];

    wire [31:0] ram_rdata_q = {q3, q2, q1, q0};

    // ------------------------------------------------------------- the result
    // mmio reads combinationally during the access cycle, so register it here
    // to line it up with the RAM's output register. Both are captured on the
    // same edge, and so is the select, which means o_rdata is already settled
    // on the cycle mem_pipe asserts o_valid.
    reg [31:0] mmio_rdata_q;
    reg        sel_mmio_q;

    always @(posedge i_clk) begin
        mmio_rdata_q <= i_mmio_rdata;
        sel_mmio_q   <= acc_mmio;
    end

    assign o_rdata = sel_mmio_q ? mmio_rdata_q : ram_rdata_q;

endmodule

`default_nettype wire
