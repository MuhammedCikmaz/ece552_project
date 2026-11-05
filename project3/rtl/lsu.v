`default_nettype none

// Combinational adapter for the testbench's aligned, byte-masked memory port.
// The low address bits select fixed wiring; no variable shifts are needed.
module lsu (
    input  wire [31:0] i_addr,
    input  wire [31:0] i_store_data,
    input  wire [31:0] i_mem_data,
    input  wire [ 2:0] i_funct3,
    output wire [31:0] o_addr,
    output wire [ 3:0] o_mask,
    output wire [31:0] o_store_data,
    output wire [31:0] o_load_data,
    output wire        o_misaligned
);
    wire [1:0] offset = i_addr[1:0];
    wire is_byte = (i_funct3[1:0] == 2'b00);
    wire is_half = (i_funct3[1:0] == 2'b01);
    wire is_word = (i_funct3[1:0] == 2'b10);

    wire [3:0] byte_mask = (offset == 2'b00) ? 4'b0001 :
                           (offset == 2'b01) ? 4'b0010 :
                           (offset == 2'b10) ? 4'b0100 : 4'b1000;
    wire [3:0] half_mask = offset[1] ? 4'b1100 : 4'b0011;
    assign o_addr = {i_addr[31:2], 2'b00};
    assign o_mask = is_byte ? byte_mask : is_half ? half_mask : 4'b1111;
    assign o_misaligned = (is_half & offset[0]) |
                          (is_word & (offset != 2'b00));

    assign o_store_data = (offset == 2'b00) ? i_store_data :
                          (offset == 2'b01) ? {i_store_data[23:0], 8'b0} :
                          (offset == 2'b10) ? {i_store_data[15:0], 16'b0} :
                                             {i_store_data[7:0], 24'b0};
    wire [31:0] selected = (offset == 2'b00) ? i_mem_data :
                           (offset == 2'b01) ? {8'b0, i_mem_data[31:8]} :
                           (offset == 2'b10) ? {16'b0, i_mem_data[31:16]} :
                                              {24'b0, i_mem_data[31:24]};
    wire byte_sign = ~i_funct3[2] & selected[7];
    wire half_sign = ~i_funct3[2] & selected[15];
    assign o_load_data = is_byte ? {{24{byte_sign}}, selected[7:0]} :
                         is_half ? {{16{half_sign}}, selected[15:0]} : selected;
endmodule

`default_nettype wire
