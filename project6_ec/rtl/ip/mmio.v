// Memory-mapped I/O block.
//
// Decoded at 0x8000_0000 (anything with address bit 31 set). Reads are
// combinational and writes land on the next edge, exactly as in the Project 3
// demo -- this block did not need changing for a multi-cycle memory. The
// request/response handshake your hart sees is produced by dbus.v, which
// drives this block at its access stage and registers the read on the way
// back out. Byte masks are ignored; peripheral registers are word access only.
//
//   0x00  LEDR      W   10 bits
//   0x04  SW        R   10 bits, synchronised
//   0x08  KEY       R    4 bits, synchronised, active high (board is active low)
//   0x0C  KEY_EDGE  R    4 bits, sticky press latch
//   0x10  KEY_ACK   W    write 1 to a bit to clear that latch bit
//   0x14  HEX_VAL   W   24 bits -> six hex digits, HEX5..HEX0
//   0x18  reserved      (raw segment access, for letters -- not built yet)
//   0x1C  reserved
//   0x20  HEX_EN    W    6 bits, per-digit blanking; resets to all-on
//   0x24  CYCLES    R   free-running cycle counter
//   0x28  INSTRET   R   retired instruction counter
//   0x2C  MEM_CFG   R   memory timing in force:
//                          [ 3:0] instruction memory latency, 1 to 8
//                          [ 7:4] data memory latency, 1 to 8
//                          [11:8] initiation interval, 1 to 4 (both memories)
//
// CYCLES and INSTRET exist because this ISA has no CSRs -- there is no rdcycle
// or rdinstret to read. Together they are how cpi.c measures CPI on real
// hardware: sample both, run a workload, sample both again, divide.
//
// MEM_CFG reports the memory timing actually in force, sampled from the
// switches at reset (see soc_core.v). A program can therefore label its own
// measurement with the configuration that produced it, instead of relying on
// whoever is standing at the board to remember where the switches were.
//
// The two memories have *independent* latencies, which is what makes the
// demo experiment possible: instruction fetch latency is paid once per
// instruction, data latency only by the instructions that touch memory, and
// separating the two knobs is the only way to see which one dominates. The
// initiation interval is shared by both.
//
// KEY_EDGE is a sticky latch cleared by an explicit write to KEY_ACK, rather
// than being cleared by the read itself. Read-to-clear would be safe on a
// single-cycle processor but would lose presses on a pipelined one that can
// replay a load.

`default_nettype none

module mmio (
    input  wire        i_clk,
    input  wire        i_rst,

    // dmem-style port, driven by dbus.v at its access stage
    input  wire [31:0] i_addr,
    input  wire        i_ren,
    input  wire        i_wen,
    input  wire [31:0] i_wdata,
    output reg  [31:0] o_rdata,

    // the memory timing in force, for MEM_CFG readback
    input  wire [ 3:0] i_cfg_ilatency,
    input  wire [ 3:0] i_cfg_dlatency,
    input  wire [ 3:0] i_cfg_interval,

    // raw board inputs, still active low for KEY
    input  wire [ 9:0] i_sw_raw,
    input  wire [ 3:0] i_key_raw_n,

    // retired-instruction strobe, for the INSTRET counter
    input  wire        i_retire,

    // outputs to the board
    output reg  [ 9:0] o_ledr,
    output reg  [23:0] o_hex_val,
    output reg  [ 5:0] o_hex_en
);
    localparam ADDR_LEDR     = 6'h00 >> 2;
    localparam ADDR_SW       = 6'h04 >> 2;
    localparam ADDR_KEY      = 6'h08 >> 2;
    localparam ADDR_KEY_EDGE = 6'h0C >> 2;
    localparam ADDR_KEY_ACK  = 6'h10 >> 2;
    localparam ADDR_HEX_VAL  = 6'h14 >> 2;
    localparam ADDR_HEX_EN   = 6'h20 >> 2;
    localparam ADDR_CYCLES   = 6'h24 >> 2;
    localparam ADDR_INSTRET  = 6'h28 >> 2;
    localparam ADDR_MEM_CFG  = 6'h2C >> 2;

    wire [3:0] reg_idx = i_addr[5:2];

    // ---------------------------------------------------------------- inputs
    // Two-stage synchronisers. The board debounces KEY in hardware with a
    // Schmitt trigger, so no debounce logic is needed here -- only metastability
    // protection, since these are asynchronous to our clock.
    reg [9:0] sw_meta, sw_sync;
    reg [3:0] key_meta, key_sync, key_prev;

    always @(posedge i_clk) begin
        sw_meta  <= i_sw_raw;
        sw_sync  <= sw_meta;
        key_meta <= ~i_key_raw_n;   // invert once, here: active high everywhere above
        key_sync <= key_meta;
        key_prev <= key_sync;
    end

    wire [3:0] key_rise = key_sync & ~key_prev;

    // ------------------------------------------------------------- registers
    reg [3:0]  key_edge;
    reg [31:0] cycles;
    reg [31:0] instret;

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_ledr    <= 10'd0;
            o_hex_val <= 24'd0;
            o_hex_en  <= 6'h3F;     // all digits on until a program says otherwise
            key_edge  <= 4'd0;
            cycles    <= 32'd0;
            instret   <= 32'd0;
        end else begin
            cycles  <= cycles + 32'd1;
            if (i_retire)
                instret <= instret + 32'd1;

            // Latch new presses; a write to KEY_ACK in the same cycle must not
            // swallow an edge arriving now, so set takes priority over clear.
            if (i_wen && reg_idx == ADDR_KEY_ACK)
                key_edge <= (key_edge & ~i_wdata[3:0]) | key_rise;
            else
                key_edge <= key_edge | key_rise;

            if (i_wen) begin
                case (reg_idx)
                    ADDR_LEDR:    o_ledr    <= i_wdata[9:0];
                    ADDR_HEX_VAL: o_hex_val <= i_wdata[23:0];
                    ADDR_HEX_EN:  o_hex_en  <= i_wdata[5:0];
                    default:      ;
                endcase
            end
        end
    end

    // ------------------------------------------------------------------ read
    always @(*) begin
        case (reg_idx)
            ADDR_SW:       o_rdata = {22'd0, sw_sync};
            ADDR_KEY:      o_rdata = {28'd0, key_sync};
            ADDR_KEY_EDGE: o_rdata = {28'd0, key_edge};
            ADDR_CYCLES:   o_rdata = cycles;
            ADDR_INSTRET:  o_rdata = instret;
            ADDR_MEM_CFG:  o_rdata = {20'd0, i_cfg_interval,
                                              i_cfg_dlatency, i_cfg_ilatency};
            ADDR_LEDR:     o_rdata = {22'd0, o_ledr};
            ADDR_HEX_VAL:  o_rdata = {8'd0, o_hex_val};
            ADDR_HEX_EN:   o_rdata = {26'd0, o_hex_en};
            default:       o_rdata = 32'd0;
        endcase
    end

endmodule

`default_nettype wire
