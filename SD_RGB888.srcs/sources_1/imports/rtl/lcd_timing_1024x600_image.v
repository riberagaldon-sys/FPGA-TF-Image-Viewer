`timescale 1ns/1ps
`default_nettype none

// 1024x600 timing matched to the verified Game project.
// 51.2 MHz pixel clock, H total 1344, V total 635.
// The target panel is operated in DE mode, so HSYNC/VSYNC are held inactive
// (logic high) exactly as in lcd_timing_1024x600_frame from the known-good
// Game project.  This removes any residual ambiguity from redundant sync pulses.
module lcd_timing_1024x600_image(
    input  wire        pix_clk,
    input  wire        rst_n,
    output wire [10:0] x,
    output wire [9:0]  y,
    output wire        active_video,
    output wire        hsync,
    output wire        vsync,
    output wire        frame_start
);
    localparam integer H_SYNC   = 20;
    localparam integer H_BP     = 140;
    localparam integer H_ACTIVE = 1024;
    localparam integer H_FP     = 160;
    localparam integer H_TOTAL  = H_SYNC + H_BP + H_ACTIVE + H_FP;

    localparam integer V_SYNC   = 3;
    localparam integer V_BP     = 20;
    localparam integer V_ACTIVE = 600;
    localparam integer V_FP     = 12;
    localparam integer V_TOTAL  = V_SYNC + V_BP + V_ACTIVE + V_FP;

    reg [10:0] h_count;
    reg [9:0]  v_count;

    wire h_active =
        (h_count >= H_SYNC + H_BP) &&
        (h_count <  H_SYNC + H_BP + H_ACTIVE);
    wire v_active =
        (v_count >= V_SYNC + V_BP) &&
        (v_count <  V_SYNC + V_BP + V_ACTIVE);

    assign active_video = h_active && v_active;
    assign x = h_active ? (h_count - (H_SYNC + H_BP)) : 11'd0;
    assign y = v_active ? (v_count - (V_SYNC + V_BP)) : 10'd0;

    // DE-mode interface: same as the verified Game project.
    assign hsync = 1'b1;
    assign vsync = 1'b1;

    assign frame_start =
        (h_count == H_SYNC + H_BP) &&
        (v_count == V_SYNC + V_BP);

    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 11'd0;
            v_count <= 10'd0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 11'd0;
                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 10'd1;
            end else begin
                h_count <= h_count + 11'd1;
            end
        end
    end
endmodule

`default_nettype wire
