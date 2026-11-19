// =============================================================================
//  THIS IS THE ONLY FILE YOU NEED TO EDIT.
// =============================================================================
// -----------------------------------------------------------------------------
//  WHAT CONNECTS TO WHAT
// -----------------------------------------------------------------------------
//
//  Your hart port        Connect to           Why
//  -------------------   ------------------   ---------------------------------
//  i_clk                 i_clk                the CPU clock, already divided
//                                             down from the board's 50 MHz
//  i_rst                 i_rst                synchronous, active high
//
//  i_imem_ready          imem_ready           high when the memory can take a
//                                             new fetch this cycle
//  o_imem_raddr          imem_raddr           your PC goes out here
//  o_imem_ren            imem_ren             assert to request a fetch; only
//                                             legal when imem_ready is high
//  i_imem_valid          imem_valid           high on the cycle the instruction
//                                             comes back
//  i_imem_rdata          imem_rdata           the instruction word itself,
//                                             valid only when imem_valid is
//
//  i_dmem_ready          dmem_ready           high when the memory can take a
//                                             new load or store this cycle
//  o_dmem_addr           dmem_addr            word-aligned byte address
//  o_dmem_ren            dmem_ren             asserted for loads
//  o_dmem_wen            dmem_wen             asserted for stores
//  o_dmem_wdata          dmem_wdata           store data
//  o_dmem_mask           dmem_mask            which byte lanes (sb / sh / sw)
//  i_dmem_valid          dmem_valid           high on the cycle load data
//                                             comes back
//  i_dmem_rdata          dmem_rdata           the load data itself, valid only
//                                             when dmem_valid is
//
//  o_retire_valid        o_retire_valid       pipelined: only on real retires
//  o_retire_inst         o_retire_inst        used to report traps
//  o_retire_trap         o_retire_trap        lights the error pattern
//  o_retire_halt         o_retire_halt        ebreak stops the CPU clock
//  o_retire_pc           o_retire_pc          reported on a trap
//  o_retire_rs1_raddr    retire_rs1_raddr     \
//  o_retire_rs1_rdata    retire_rs1_rdata      |
//  o_retire_rs2_raddr    retire_rs2_raddr      |
//  o_retire_rs2_rdata    retire_rs2_rdata      |  not used by the board, but
//  o_retire_rd_waddr     retire_rd_waddr       |  your hart drives them
//  o_retire_rd_wdata     retire_rd_wdata       |
//  o_retire_dmem_addr    retire_dmem_addr      |
//  o_retire_dmem_mask    retire_dmem_mask      |
//  o_retire_dmem_ren     retire_dmem_ren       |
//  o_retire_dmem_wen     retire_dmem_wen       |
//  o_retire_dmem_rdata   retire_dmem_rdata     |
//  o_retire_dmem_wdata   retire_dmem_wdata     |
//  o_retire_next_pc      retire_next_pc       /
// =============================================================================

`default_nettype none

module soc_core #(
    parameter IMEM_WORDS  = 1024,               // 4 KB
    parameter DMEM_WORDS  = 1024,               // 4 KB
    parameter MAX_LATENCY = 8,
    parameter INIT_FILE   = "program.mem",
    // dbus needs four separate per-byte-lane images rather than one
    // word-wide file -- see the storage section in ip/dbus.v for why.
    parameter DMEM_INIT_FILE0 = "program.lane0.mem",
    parameter DMEM_INIT_FILE1 = "program.lane1.mem",
    parameter DMEM_INIT_FILE2 = "program.lane2.mem",
    parameter DMEM_INIT_FILE3 = "program.lane3.mem"
) (
    input  wire        i_clk,                   // CPU clock (already divided)
    input  wire        i_rst,                   // synchronous, active high

    // raw board inputs
    input  wire [ 9:0] i_sw,
    input  wire [ 3:0] i_key_n,                 // active low, as the board wires them

    // outputs toward the board
    output wire [ 9:0] o_ledr,
    output wire [23:0] o_hex_val,
    output wire [ 5:0] o_hex_en,

    // retire interface, forwarded so the board can show halts and traps
    output wire        o_retire_valid,
    output wire        o_retire_halt,
    output wire        o_retire_trap,
    output wire [31:0] o_retire_pc,
    output wire [31:0] o_retire_inst
);
    // ------------------------------------------------------------ hart wires
    wire        imem_ready, imem_ren, imem_valid;
    wire [31:0] imem_raddr, imem_rdata;

    wire        dmem_ready, dmem_ren, dmem_wen, dmem_valid;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire [ 3:0] dmem_mask;

    // Retire signals the board does not use, but your hart still drives.
    wire [ 4:0] retire_rs1_raddr, retire_rs2_raddr, retire_rd_waddr;
    wire [31:0] retire_rs1_rdata, retire_rs2_rdata, retire_rd_wdata;
    wire [31:0] retire_next_pc;
    wire [31:0] retire_dmem_addr, retire_dmem_rdata, retire_dmem_wdata;
    wire [ 3:0] retire_dmem_mask;
    wire        retire_dmem_ren, retire_dmem_wen;

    // -------------------------------------------------------- memory timing
    reg [3:0] cfg_ilatency;
    reg [3:0] cfg_dlatency;
    reg [3:0] cfg_interval;

    reg [7:0] sw_cfg_meta, sw_cfg_sync;

    always @(posedge i_clk) begin
        sw_cfg_meta <= i_sw[7:0];
        sw_cfg_sync <= sw_cfg_meta;

        if (i_rst) begin
            cfg_ilatency <= {1'b0, sw_cfg_sync[2:0]} + 4'd1;     // 1 .. 8
            cfg_dlatency <= {1'b0, sw_cfg_sync[5:3]} + 4'd1;     // 1 .. 8
            cfg_interval <= {2'b0, sw_cfg_sync[7:6]} + 4'd1;     // 1 .. 4
        end
    end

    // =========================================================================
    //  TODO: connect your processor.
    // =========================================================================
    hart #(
        .RESET_ADDR (32'h0)                     // programs start at address 0
    ) u_hart (
        .i_clk               (                 ),
        .i_rst               (                 ),

        .i_imem_ready        (                 ),
        .o_imem_raddr        (                 ),
        .o_imem_ren          (                 ),
        .i_imem_valid        (                 ),
        .i_imem_rdata        (                 ),

        .i_dmem_ready        (                 ),
        .o_dmem_addr         (                 ),
        .o_dmem_ren          (                 ),
        .o_dmem_wen          (                 ),
        .o_dmem_wdata        (                 ),
        .o_dmem_mask         (                 ),
        .i_dmem_valid        (                 ),
        .i_dmem_rdata        (                 ),

        .o_retire_valid      (                 ),
        .o_retire_inst       (                 ),
        .o_retire_trap       (                 ),
        .o_retire_halt       (                 ),
        .o_retire_rs1_raddr  (                 ),
        .o_retire_rs1_rdata  (                 ),
        .o_retire_rs2_raddr  (                 ),
        .o_retire_rs2_rdata  (                 ),
        .o_retire_rd_waddr   (                 ),
        .o_retire_rd_wdata   (                 ),
        .o_retire_dmem_addr  (                 ),
        .o_retire_dmem_mask  (                 ),
        .o_retire_dmem_ren   (                 ),
        .o_retire_dmem_wen   (                 ),
        .o_retire_dmem_rdata (                 ),
        .o_retire_dmem_wdata (                 ),
        .o_retire_pc         (                 ),
        .o_retire_next_pc    (                 )
    );
    // =========================================================================
    //  END OF THE PART YOU EDIT
    // =========================================================================

    // ------------------------------------------------------------- memories
    imem #(
        .WORDS       (IMEM_WORDS),
        .INIT_FILE   (INIT_FILE),
        .MAX_LATENCY (MAX_LATENCY)
    ) u_imem (
        .i_clk          (i_clk),
        .i_rst          (i_rst),
        .i_cfg_latency  (cfg_ilatency),
        .i_cfg_interval (cfg_interval),

        .o_ready        (imem_ready),
        .i_raddr        (imem_raddr),
        .i_ren          (imem_ren),
        .o_valid        (imem_valid),
        .o_rdata        (imem_rdata)
    );

    wire [31:0] mmio_addr, mmio_wdata, mmio_rdata;
    wire        mmio_ren, mmio_wen;

    dbus #(
        .WORDS       (DMEM_WORDS),
        .INIT_FILE0  (DMEM_INIT_FILE0),
        .INIT_FILE1  (DMEM_INIT_FILE1),
        .INIT_FILE2  (DMEM_INIT_FILE2),
        .INIT_FILE3  (DMEM_INIT_FILE3),
        .MAX_LATENCY (MAX_LATENCY)
    ) u_dbus (
        .i_clk          (i_clk),
        .i_rst          (i_rst),
        .i_cfg_latency  (cfg_dlatency),
        .i_cfg_interval (cfg_interval),

        .o_ready        (dmem_ready),
        .i_addr         (dmem_addr),
        .i_ren          (dmem_ren),
        .i_wen          (dmem_wen),
        .i_wdata        (dmem_wdata),
        .i_mask         (dmem_mask),
        .o_valid        (dmem_valid),
        .o_rdata        (dmem_rdata),

        .o_mmio_addr    (mmio_addr),
        .o_mmio_ren     (mmio_ren),
        .o_mmio_wen     (mmio_wen),
        .o_mmio_wdata   (mmio_wdata),
        .i_mmio_rdata   (mmio_rdata)
    );

    // ----------------------------------------------------------- peripherals
    mmio u_mmio (
        .i_clk          (i_clk),
        .i_rst          (i_rst),

        .i_addr         (mmio_addr),
        .i_ren          (mmio_ren),
        .i_wen          (mmio_wen),
        .i_wdata        (mmio_wdata),
        .o_rdata        (mmio_rdata),

        .i_cfg_ilatency (cfg_ilatency),
        .i_cfg_dlatency (cfg_dlatency),
        .i_cfg_interval (cfg_interval),

        .i_sw_raw       (i_sw),
        .i_key_raw_n    (i_key_n),

        .i_retire       (o_retire_valid),

        .o_ledr         (o_ledr),
        .o_hex_val      (o_hex_val),
        .o_hex_en       (o_hex_en)
    );

endmodule

`default_nettype wire
