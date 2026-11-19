// CPU clock divider with a run enable.
//
// DIV_LOG2 = 2 gives CLOCK_50 / 4 = 12.5 MHz.
//

`default_nettype none

module clkdiv #(
    parameter DIV_LOG2 = 2
) (
    input  wire i_clk,
    input  wire i_rst,
    input  wire i_run,
    output wire o_clk
);
    reg [DIV_LOG2-1:0] cnt = {DIV_LOG2{1'b0}};

    always @(posedge i_clk) begin
        if (i_rst || i_run)
            cnt <= cnt + 1'b1;
    end

    assign o_clk = cnt[DIV_LOG2-1];

endmodule

`default_nettype wire
