// Instruction memory: 4 KB, request/response, backed by block RAM.
`default_nettype none

module imem #(
    parameter WORDS       = 1024,           // 4 KB
    parameter INIT_FILE   = "program.mem",
    parameter MAX_LATENCY = 8
) (
    input  wire        i_clk,
    input  wire        i_rst,

    input  wire [ 3:0] i_cfg_latency,
    input  wire [ 3:0] i_cfg_interval,

    // Request/response port, wired straight to the hart's imem interface.
    output wire        o_ready,
    input  wire [31:0] i_raddr,
    input  wire        i_ren,
    output wire        o_valid,
    output wire [31:0] o_rdata
);
    localparam AW = $clog2(WORDS);

    // ---------------------------------------------------------- the handshake
    // acc_ren is brought out but deliberately not used by the storage below
    // (see the always block). It is kept connected because it is the signal
    // you want to look at first when probing a fetch in a waveform.
    wire [31:0] acc_addr;
    wire        acc_ren;

    mem_pipe #(
        .MAX_LATENCY (MAX_LATENCY)
    ) u_pipe (
        .i_clk          (i_clk),
        .i_rst          (i_rst),
        .i_cfg_latency  (i_cfg_latency),
        .i_cfg_interval (i_cfg_interval),

        .o_ready        (o_ready),
        .i_addr         (i_raddr),
        .i_ren          (i_ren),
        .i_wen          (1'b0),             // instruction memory is read only
        .i_mask         (4'b1111),
        .i_wdata        (32'd0),

        .o_acc_addr     (acc_addr),
        .o_acc_ren      (acc_ren),
        .o_acc_wen      (              ),   // never written
        .o_acc_mask     (              ),   // always a full word
        .o_acc_wdata    (              ),

        .o_valid        (o_valid),
        .o_wdone        (              )    // never written
    );

    // ------------------------------------------------------------ the storage
    reg [31:0] mem [0:WORDS-1];

    initial $readmemh(INIT_FILE, mem);

    // i_raddr is a byte address; drop the two low bits to index words.
    wire [AW-1:0] idx = acc_addr[AW+1:2];

    reg [31:0] rdata_q;

    always @(posedge i_clk) begin
        rdata_q <= mem[idx];
    end

    assign o_rdata = rdata_q;

endmodule

`default_nettype wire
