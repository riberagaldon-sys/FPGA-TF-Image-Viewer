`timescale 1ns/1ps
`default_nettype none

// One full 1024x600 RGB565 framebuffer = 614,400 x 16 bits = 9.83 Mbit.
// This is intentionally the original proven single inferred dual-port BRAM
// implementation. Do not split it into banks: the banked revisions caused
// visible pixel corruption on the target board and added BRAM rounding cost.
// Write port: 50 MHz SD/FAT domain.
// Read port : 51.2 MHz LCD pixel domain.
module rgb565_framebuffer_dp #(
    parameter integer FRAME_PIXELS = 614400,
    parameter integer ADDR_W       = 20
)(
    input  wire                 wr_clk,
    input  wire                 wr_en,
    input  wire [ADDR_W-1:0]    wr_addr,
    input  wire [15:0]          wr_data,

    input  wire                 rd_clk,
    input  wire [ADDR_W-1:0]    rd_addr,
    output reg  [15:0]          rd_data
);
    (* ram_style = "block" *) reg [15:0] mem [0:FRAME_PIXELS-1];

    always @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        rd_data <= mem[rd_addr];
    end
endmodule

`default_nettype wire
