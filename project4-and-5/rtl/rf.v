`default_nettype none

// The register file is effectively a single cycle memory with 32-bit words
// and depth 32. It has two asynchronous read ports, allowing two independent
// registers to be read at the same time combinationally, and one synchronous
// write port, allowing a register to be written to on the next clock edge.
// The register `x0` is hardwired to zero, and writes to it are ignored.
module rf #(
    // When this parameter is set to 1, "RF bypass" mode is enabled. This
    // allows data at the write port to be observed at the read ports
    // immediately without having to wait for the next clock edge. This is
    // useful in a pipeline, but feeding a single-cycle instruction's result
    // straight back into its own source reads can create a combinational loop.
    //
    // The current hart.v selects 0. The Fall 2026 Project 4 specification
    // permits enabling RF bypass starting in Step 1; it is optional.
    // This bypass only connects the RF write port to its read ports. It does
    // not forward results from other pipeline stages.
    parameter BYPASS_EN = 0
) (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset.
    input  wire        i_rst,
    // Both read register ports are asynchronous (zero-cycle). That is, read
    // data is visible combinationally without having to wait for a clock.
    //
    // Register read port 1, with input address [0, 31] and output data.
    input  wire [ 4:0] i_rs1_raddr,
    output wire [31:0] o_rs1_rdata,
    // Register read port 2, with input address [0, 31] and output data.
    input  wire [ 4:0] i_rs2_raddr,
    output wire [31:0] o_rs2_rdata,
    // The register write port is synchronous. When write is enabled, the
    // write data is visible after the next clock edge.
    //
    // Write register enable, address [0, 31] and input data.
    input  wire        i_rd_wen,
    input  wire [ 4:0] i_rd_waddr,
    input  wire [31:0] i_rd_wdata
);
    // Storage for x1-x31. x0 is hardwired to zero below and never stored.
    reg [31:0] mem [1:31];

    // generate builds 31 separate clocked register blocks when the design is
    // elaborated. It is not a loop that runs across 31 execution cycles.
    // At each rising edge, reset clears every register; otherwise only the
    // addressed register with write enable asserted accepts the new value.
    genvar i;
    generate
        for (i = 1; i < 32; i = i + 1) begin : gen_reg
            always @(posedge i_clk) begin
                if (i_rst) begin
                    mem[i] <= 32'b0;
                end else if (i_rd_wen && (i_rd_waddr == i[4:0])) begin
                    mem[i] <= i_rd_wdata;
                end
            end
        end
    endgenerate

    // Reads select a stored value immediately, without waiting for a clock.
    // Selecting x0 returns a literal zero instead of reading the array.
    wire [31:0] rs1_direct = (i_rs1_raddr == 5'd0) ? 32'b0 : mem[i_rs1_raddr];
    wire [31:0] rs2_direct = (i_rs2_raddr == 5'd0) ? 32'b0 : mem[i_rs2_raddr];

    // BYPASS_EN is a build-time parameter, not a signal that changes per cycle.
    // With bypass enabled, a read matching an enabled nonzero destination
    // sees the incoming write value before it is stored at the clock edge.
    generate
        if (BYPASS_EN) begin : gen_bypass
            wire bypass1 = i_rd_wen && (i_rd_waddr != 5'd0) && (i_rd_waddr == i_rs1_raddr);
            wire bypass2 = i_rd_wen && (i_rd_waddr != 5'd0) && (i_rd_waddr == i_rs2_raddr);
            assign o_rs1_rdata = bypass1 ? i_rd_wdata : rs1_direct;
            assign o_rs2_rdata = bypass2 ? i_rd_wdata : rs2_direct;
        end else begin : gen_nobypass
            assign o_rs1_rdata = rs1_direct;
            assign o_rs2_rdata = rs2_direct;
        end
    endgenerate
endmodule

`default_nettype wire
