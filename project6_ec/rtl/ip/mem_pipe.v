// Multi-cycle memory handshake engine.
//
// -----------------------------------------------------------------------------
//  TIMING
// -----------------------------------------------------------------------------
// So a response arrives LATENCY cycles after the request was accepted.
//
// o_ready drops for INTERVAL-1 cycles after each accepted request, so a new
// request can start every INTERVAL cycles. With LATENCY > INTERVAL there is
// more than one request in flight at a time; each occupies a different stage
// of the shift register below, so they never collide and the storage behind
// this module still only needs a single port.
//
// LATENCY = 1 is the floor.
//
// -----------------------------------------------------------------------------
//  CONFIGURATION
// -----------------------------------------------------------------------------
//
// i_cfg_latency and i_cfg_interval are quasi-static: they are sampled from the
// switches while reset is asserted (see soc_core.v) and then held. 

`default_nettype none

module mem_pipe #(
    // Deepest latency the shift register can hold. The configuration fields
    // are four bits wide, so this must be between 1 and 15.
    parameter MAX_LATENCY = 8
) (
    input  wire        i_clk,
    input  wire        i_rst,

    // Quasi-static configuration. Clamped internally, so a nonsense value
    // degrades to the nearest legal one rather than producing X.
    input  wire [ 3:0] i_cfg_latency,          // 1 .. MAX_LATENCY
    input  wire [ 3:0] i_cfg_interval,         // 1 .. 15

    // Request port, facing the processor.
    output wire        o_ready,
    input  wire [31:0] i_addr,
    input  wire        i_ren,
    input  wire        i_wen,
    input  wire [ 3:0] i_mask,
    input  wire [31:0] i_wdata,

    // Access taps, facing the storage. Present the request during cycle
    // LATENCY-1; the storage is expected to register them.
    output wire [31:0] o_acc_addr,
    output wire        o_acc_ren,
    output wire        o_acc_wen,
    output wire [ 3:0] o_acc_mask,
    output wire [31:0] o_acc_wdata,

    // Response strobes, one cycle after the access taps -- aligned with the
    // storage's output register.
    output wire        o_valid,
    output wire        o_wdone
);
    // ----------------------------------------------------------------- config
    wire [3:0] lat = (i_cfg_latency < 4'd1)        ? 4'd1
                   : (i_cfg_latency > MAX_LATENCY) ? MAX_LATENCY[3:0]
                   :                                 i_cfg_latency;

    wire [3:0] ivl = (i_cfg_interval < 4'd1) ? 4'd1 : i_cfg_interval;

    // -------------------------------------------------------------- interval
    reg [3:0] ivl_cnt;

    assign o_ready = ~i_rst & (ivl_cnt == 4'd0);

    always @(posedge i_clk) begin
        if (i_rst)
            ivl_cnt <= 4'd0;
        else if (ivl_cnt >= ivl - 4'd1)
            ivl_cnt <= 4'd0;
        else if (~o_ready | i_ren | i_wen)
            ivl_cnt <= ivl_cnt + 4'd1;
    end

    // ------------------------------------------------------ in-flight stages
    wire        s0_ren = o_ready & i_ren;
    wire        s0_wen = o_ready & i_wen;

    reg [31:0] st_addr  [1:MAX_LATENCY];
    reg        st_ren   [1:MAX_LATENCY];
    reg        st_wen   [1:MAX_LATENCY];
    reg [ 3:0] st_mask  [1:MAX_LATENCY];
    reg [31:0] st_wdata [1:MAX_LATENCY];

    // Only ren/wen need resetting; they gate the validity of everything else.
    always @(posedge i_clk) begin
        if (i_rst) begin
            st_ren  [1] <= 1'b0;
            st_wen  [1] <= 1'b0;
        end else begin
            st_addr [1] <= i_addr;
            st_ren  [1] <= s0_ren;
            st_wen  [1] <= s0_wen;
            st_mask [1] <= i_mask;
            st_wdata[1] <= i_wdata;
        end
    end

    genvar k;
    generate for (k = 2; k <= MAX_LATENCY; k = k + 1) begin : stage
        always @(posedge i_clk) begin
            if (i_rst) begin
                st_ren  [k] <= 1'b0;
                st_wen  [k] <= 1'b0;
            end else begin
                st_addr [k] <= st_addr [k-1];
                st_ren  [k] <= st_ren  [k-1];
                st_wen  [k] <= st_wen  [k-1];
                st_mask [k] <= st_mask [k-1];
                st_wdata[k] <= st_wdata[k-1];
            end
        end
    end endgenerate

    // ----------------------------------------------------------- access taps
    reg [31:0] acc_addr;
    reg        acc_ren, acc_wen;
    reg [ 3:0] acc_mask;
    reg [31:0] acc_wdata;

    always @(*) begin
        if (lat == 4'd1) begin
            acc_addr  = i_addr;
            acc_ren   = s0_ren;
            acc_wen   = s0_wen;
            acc_mask  = i_mask;
            acc_wdata = i_wdata;
        end else begin
            acc_addr  = st_addr [lat - 4'd1];
            acc_ren   = st_ren  [lat - 4'd1];
            acc_wen   = st_wen  [lat - 4'd1];
            acc_mask  = st_mask [lat - 4'd1];
            acc_wdata = st_wdata[lat - 4'd1];
        end
    end

    assign o_acc_addr  = acc_addr;
    assign o_acc_ren   = acc_ren;
    assign o_acc_wen   = acc_wen;
    assign o_acc_mask  = acc_mask;
    assign o_acc_wdata = acc_wdata;

    // ------------------------------------------------------------- responses
    assign o_valid = st_ren[lat];
    assign o_wdone = st_wen[lat];

endmodule

`default_nettype wire
