`timescale 1ns/1ps
`default_nettype none

// GX-BIDT + XC7A200T + 1024x600 RGB888 panel
// Stable SD-card image viewer, quality/stability revision.
//
// Preferred SD-card file format:
//   PIC01.BIN ... PICnn.BIN
//   1024x600 packed RGB666, 18 bits/pixel, LSB-first bitstream
//   exact size = 1,382,400 bytes.
//
// Legacy RGB565 little-endian files (1,228,800 bytes) are also accepted.
//
// IMPORTANT STABILITY CHANGE:
// The LCD pins remain RGB888, but the on-chip full-frame buffer is RGB565.
// RGB666 files are accepted and reduced to RGB565 only when they are written
// into BRAM.  This restores the original proven 16-bit BRAM organization and
// leaves substantially more routing/BRAM margin on XC7A200T.  It avoids the
// near-full 18-bit framebuffer that caused unstable/jagged pixels in hardware.
//
// Controls:
//   UP     (S1_KEYA) : start forward auto-play
//   DOWN   (S1_KEYD) : start reverse auto-play
//   LEFT   (S1_KEYB) : previous image and stop auto-play
//   RIGHT  (S1_KEYC) : next image and stop auto-play
//   CENTER (S1_KEYP) : stop auto-play and reload current image
// Auto-play holds each fully-loaded picture for AUTO_INTERVAL_SEC seconds.
//
// Image changes use a frame-boundary blank handshake. The current frame is
// kept intact until the next LCD frame boundary; only after the LCD is blank
// may the SD/FAT side overwrite the single framebuffer. The new image becomes
// visible only at a later frame boundary after the complete frame is loaded.
// This prevents old/new-frame tearing and mid-frame ghosting.
module top_sd_rgb888_image_viewer #(
    parameter integer CLK_HZ          = 50_000_000,
    parameter integer POR_BITS        = 21,
    parameter integer IMAGE_COUNT       = 2,
    parameter integer SD_DATA_SPI_HZ    = 12_500_000,
    parameter integer AUTO_INTERVAL_SEC = 5
)(
    input  wire       sys_clk,

    input  wire       S1_KEYA,
    input  wire       S1_KEYB,
    input  wire       S1_KEYC,
    input  wire       S1_KEYD,
    input  wire       S1_KEYP,

    output wire [7:0] LCD_R,
    output wire [7:0] LCD_G,
    output wire [7:0] LCD_B,
    output wire       LCD_CLK,
    output wire       LCD_HSYNC,
    output wire       LCD_VSYNC,
    output wire       LCD_DE,
    output wire       LCD_BL,
    output wire       LCD_nRST,

    output wire       SD_CS_N,
    output wire       SD_SCLK,
    output wire       SD_MOSI,
    input  wire       SD_MISO,

    output wire [4:0] led
);
    localparam integer FRAME_W              = 1024;
    localparam integer FRAME_H              = 600;
    localparam integer FRAME_PIXELS         = FRAME_W * FRAME_H;
    localparam integer FRAME_BYTES_RGB565   = FRAME_PIXELS * 2;
    localparam integer FRAME_BITS_RGB666    = FRAME_PIXELS * 18;
    localparam integer FRAME_BYTES_RGB666   = FRAME_BITS_RGB666 / 8;
    localparam integer FB_ADDR_W            = 20;
    localparam integer AUTO_INTERVAL_TICKS = CLK_HZ * AUTO_INTERVAL_SEC;

    localparam [1:0] AUTO_OFF     = 2'd0;
    localparam [1:0] AUTO_FORWARD = 2'd1;
    localparam [1:0] AUTO_REVERSE = 2'd2;

    // ---------------------------------------------------------------------
    // Power-on reset in the 50 MHz system domain.
    // ---------------------------------------------------------------------
    wire sys_rst_n;
    por_reset #(.COUNTER_BITS(POR_BITS)) u_por (
        .clk(sys_clk), .rst_n(sys_rst_n)
    );

    // ---------------------------------------------------------------------
    // Verified Game-project LCD clock: 50 MHz -> 51.2 MHz.
    // ---------------------------------------------------------------------
    wire lcd_pix_clk_mmcm;
    wire lcd_pix_clk;
    wire lcd_clk_fb_mmcm;
    wire lcd_clk_fb;
    wire lcd_clk_locked;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(20.000),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(16.000),
        .CLKOUT0_DIVIDE_F(15.625),
        .STARTUP_WAIT("FALSE")
    ) u_lcd_mmcm (
        .CLKIN1(sys_clk),
        .CLKFBIN(lcd_clk_fb),
        .RST(~sys_rst_n),
        .PWRDWN(1'b0),
        .CLKOUT0(lcd_pix_clk_mmcm),
        .CLKFBOUT(lcd_clk_fb_mmcm),
        .LOCKED(lcd_clk_locked)
    );

    BUFG u_lcd_clk_fb_buf  (.I(lcd_clk_fb_mmcm),  .O(lcd_clk_fb));
    BUFG u_lcd_pix_clk_buf (.I(lcd_pix_clk_mmcm), .O(lcd_pix_clk));

    (* ASYNC_REG = "TRUE" *) reg [2:0] lcd_reset_sync;
    always @(posedge lcd_pix_clk or negedge lcd_clk_locked) begin
        if (!lcd_clk_locked)
            lcd_reset_sync <= 3'b000;
        else
            lcd_reset_sync <= {lcd_reset_sync[1:0], 1'b1};
    end
    wire lcd_logic_rst_n = lcd_reset_sync[2];

    // ---------------------------------------------------------------------
    // Buttons (active-low on GX-BIDT).
    // ---------------------------------------------------------------------
    wire key_up_press;
    wire key_down_press;
    wire key_left_press;
    wire key_right_press;
    wire key_reload_press;
    wire unused_up_level, unused_up_release;
    wire unused_down_level, unused_down_release;
    wire unused_left_level, unused_left_release;
    wire unused_right_level, unused_right_release;
    wire unused_reload_level, unused_reload_release;

    debounce_event #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(20), .ACTIVE_LOW(1)) u_key_up (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_in(S1_KEYA),
        .key_level(unused_up_level), .press_pulse(key_up_press),
        .release_pulse(unused_up_release)
    );
    debounce_event #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(20), .ACTIVE_LOW(1)) u_key_left (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_in(S1_KEYB),
        .key_level(unused_left_level), .press_pulse(key_left_press),
        .release_pulse(unused_left_release)
    );
    debounce_event #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(20), .ACTIVE_LOW(1)) u_key_right (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_in(S1_KEYC),
        .key_level(unused_right_level), .press_pulse(key_right_press),
        .release_pulse(unused_right_release)
    );
    debounce_event #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(20), .ACTIVE_LOW(1)) u_key_down (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_in(S1_KEYD),
        .key_level(unused_down_level), .press_pulse(key_down_press),
        .release_pulse(unused_down_release)
    );
    debounce_event #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(20), .ACTIVE_LOW(1)) u_key_reload (
        .clk(sys_clk), .rst_n(sys_rst_n), .key_in(S1_KEYP),
        .key_level(unused_reload_level), .press_pulse(key_reload_press),
        .release_pulse(unused_reload_release)
    );

    // ---------------------------------------------------------------------
    // SD block reader. Keep the proven 12.5 MHz data clock by default.
    // Raising this to 25 MHz caused some cards/board combinations to stop
    // delivering a complete frame, which leaves the image path blank.
    // ---------------------------------------------------------------------
    wire        sd_block_ready;
    wire        sd_read_busy;
    wire        sd_read_done;
    wire        sd_data_valid;
    wire [8:0]  sd_data_index;
    wire [7:0]  sd_data_byte;
    wire        sd_init_done;
    wire        sd_init_ok;
    wire        sd_card_sdhc;
    wire [7:0]  sd_error_code;

    wire        fat_block_read_req;
    wire [31:0] fat_block_read_lba;

    sd_spi_block_reader #(
        .CLK_HZ(CLK_HZ),
        .INIT_SPI_HZ(400_000),
        .DATA_SPI_HZ(SD_DATA_SPI_HZ)
    ) u_sd (
        .clk(sys_clk), .rst_n(sys_rst_n),
        .sd_cs_n(SD_CS_N), .sd_sclk(SD_SCLK), .sd_mosi(SD_MOSI),
        .sd_miso(SD_MISO),
        .read_req(fat_block_read_req), .read_lba(fat_block_read_lba),
        .ready(sd_block_ready), .read_busy(sd_read_busy), .read_done(sd_read_done),
        .data_valid(sd_data_valid), .data_index(sd_data_index),
        .data_byte(sd_data_byte),
        .init_done(sd_init_done), .init_ok(sd_init_ok),
        .card_sdhc(sd_card_sdhc), .error_code(sd_error_code)
    );

    // ---------------------------------------------------------------------
    // Image selection and frame-boundary blank handshake.
    // The FAT reader is not restarted until the LCD confirms that it blanked
    // at a clean frame boundary. This prevents writes from touching the frame
    // while it is still being scanned to the panel.
    // ---------------------------------------------------------------------
    reg [6:0] image_number;
    reg [3:0] fat_reset_count;
    reg       frame_ready_sys;
    reg       loader_error;
    reg       switch_pending;
    reg       blank_request_sys;
    reg [1:0] auto_mode;
    reg [31:0] auto_counter;

    wire fat_rst_n = sys_rst_n && (fat_reset_count == 4'd0);

    wire fat_mount_done;
    wire fat_file_found;
    wire fat_playing;
    wire fat_eof;
    wire [31:0] fat_file_size;
    wire [31:0] fat_bytes_sent;
    wire [7:0] fat_error_code;
    wire fat_out_valid;
    wire [7:0] fat_out_byte;

    wire can_change_image = frame_ready_sys ||
                            (((loader_error || (fat_error_code != 8'h00)) &&
                              !fat_playing && !sd_read_busy));

    // Auto-play timing starts only while a complete frame is stable and
    // visible. Loading/blanking time is therefore NOT counted as part of the
    // requested five-second picture interval.
    wire auto_timer_active = (auto_mode != AUTO_OFF) && frame_ready_sys &&
                             !blank_request_sys && !switch_pending &&
                             !fat_playing;
    wire auto_advance_request = auto_timer_active &&
        (auto_counter >= (AUTO_INTERVAL_TICKS - 1));

    wire manual_select_event = key_left_press || key_right_press ||
                               key_reload_press;
    wire select_event = can_change_image &&
                        (manual_select_event || auto_advance_request);

    // LCD-domain acknowledgement is synchronized back below.
    reg blank_ack_lcd;
    (* ASYNC_REG = "TRUE" *) reg [2:0] blank_ack_sync;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            blank_ack_sync <= 3'b000;
        else
            blank_ack_sync <= {blank_ack_sync[1:0], blank_ack_lcd};
    end

    // 50 MHz system-domain slideshow timer. It is reset after every image
    // change and whenever auto-play direction is changed.
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            auto_counter <= 32'd0;
        end else if ((auto_mode == AUTO_OFF) || key_up_press ||
                     key_down_press || select_event || !auto_timer_active) begin
            auto_counter <= 32'd0;
        end else if (auto_counter < (AUTO_INTERVAL_TICKS - 1)) begin
            auto_counter <= auto_counter + 1'b1;
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            image_number      <= 7'd1;
            fat_reset_count   <= 4'd8;
            switch_pending    <= 1'b0;
            blank_request_sys <= 1'b0;
            auto_mode         <= AUTO_OFF;
        end else begin
            if (fat_reset_count != 4'd0)
                fat_reset_count <= fat_reset_count - 1'b1;

            // UP starts forward slideshow; DOWN starts reverse slideshow.
            // Any manual LEFT/RIGHT/CENTER action stops auto-play.
            if (key_up_press)
                auto_mode <= AUTO_FORWARD;
            else if (key_down_press)
                auto_mode <= AUTO_REVERSE;
            else if (manual_select_event)
                auto_mode <= AUTO_OFF;

            if (select_event) begin
                if (key_left_press ||
                    (auto_advance_request && (auto_mode == AUTO_REVERSE))) begin
                    if (image_number <= 7'd1)
                        image_number <= IMAGE_COUNT;
                    else
                        image_number <= image_number - 1'b1;
                end else if (key_right_press ||
                             (auto_advance_request && (auto_mode == AUTO_FORWARD))) begin
                    if (image_number >= IMAGE_COUNT)
                        image_number <= 7'd1;
                    else
                        image_number <= image_number + 1'b1;
                end
                // CENTER keeps image_number unchanged.
                switch_pending    <= 1'b1;
                blank_request_sys <= 1'b1;
            end else if (switch_pending && blank_ack_sync[2]) begin
                // The LCD is now safely blank. Restart the FAT reader and load.
                fat_reset_count <= 4'd8;
                switch_pending  <= 1'b0;
            end

            // Keep the LCD blank for the whole load. Release it only after the
            // complete replacement frame has been committed to the framebuffer.
            if (blank_request_sys && !switch_pending && frame_ready_sys)
                blank_request_sys <= 1'b0;
        end
    end

    fat32_pic_bin_reader u_fat (
        .clk(sys_clk), .rst_n(fat_rst_n), .file_number(image_number),
        .sd_init_ok(sd_init_ok), .sd_error_code(sd_error_code),
        .block_ready(sd_block_ready),
        .block_read_req(fat_block_read_req), .block_read_lba(fat_block_read_lba),
        .block_data_valid(sd_data_valid), .block_data_index(sd_data_index),
        .block_data_byte(sd_data_byte), .block_read_done(sd_read_done),
        .sector_allow(1'b1),
        .out_valid(fat_out_valid), .out_byte(fat_out_byte),
        .mount_done(fat_mount_done), .file_found(fat_file_found),
        .playing(fat_playing), .eof(fat_eof), .file_size(fat_file_size),
        .bytes_sent(fat_bytes_sent), .error_code(fat_error_code)
    );

    // ---------------------------------------------------------------------
    // Stream decoder. RGB666/RGB565 files are stored in a stable RGB565 framebuffer.
    // Preferred format packs 18-bit pixels into a continuous LSB-first stream.
    // Four pixels occupy exactly nine bytes. Legacy RGB565 is also accepted.
    // ---------------------------------------------------------------------
    reg        byte_phase;
    reg [7:0]  pixel_low_byte;
    reg [31:0] bit_buffer;
    reg [5:0]  bit_count;
    reg [19:0] write_pixel_count;
    reg        fb_wr_en;
    reg [19:0] fb_wr_addr;
    reg [15:0] fb_wr_data;
    reg        size_checked;
    reg        size_ok;
    reg        format_rgb666;
    reg        format_rgb565;

    wire [31:0] bit_buffer_with_byte =
        bit_buffer | ({24'd0, fat_out_byte} << bit_count);
    wire [5:0] bit_count_plus_8 = bit_count + 6'd8;

    wire stream_aligned =
        (format_rgb666 && (bit_count == 0)) ||
        (format_rgb565 && !byte_phase);

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            byte_phase        <= 1'b0;
            pixel_low_byte    <= 8'd0;
            bit_buffer        <= 32'd0;
            bit_count         <= 6'd0;
            write_pixel_count <= 20'd0;
            fb_wr_en          <= 1'b0;
            fb_wr_addr        <= 20'd0;
            fb_wr_data        <= 16'd0;
            frame_ready_sys   <= 1'b0;
            loader_error      <= 1'b0;
            size_checked      <= 1'b0;
            size_ok           <= 1'b0;
            format_rgb666     <= 1'b0;
            format_rgb565     <= 1'b0;
        end else begin
            fb_wr_en <= 1'b0;

            // Hold all stream state reset from the moment a new image is
            // requested until the LCD has acknowledged a clean blank frame.
            if (select_event || switch_pending) begin
                byte_phase        <= 1'b0;
                pixel_low_byte    <= 8'd0;
                bit_buffer        <= 32'd0;
                bit_count         <= 6'd0;
                write_pixel_count <= 20'd0;
                frame_ready_sys   <= 1'b0;
                loader_error      <= 1'b0;
                size_checked      <= 1'b0;
                size_ok           <= 1'b0;
                format_rgb666     <= 1'b0;
                format_rgb565     <= 1'b0;
            end else begin
                if (!fat_rst_n) begin
                    byte_phase        <= 1'b0;
                    pixel_low_byte    <= 8'd0;
                    bit_buffer        <= 32'd0;
                    bit_count         <= 6'd0;
                    write_pixel_count <= 20'd0;
                    frame_ready_sys   <= 1'b0;
                    loader_error      <= 1'b0;
                    size_checked      <= 1'b0;
                    size_ok           <= 1'b0;
                    format_rgb666     <= 1'b0;
                    format_rgb565     <= 1'b0;
                end

                if (fat_mount_done && fat_file_found && !size_checked) begin
                    size_checked  <= 1'b1;
                    size_ok       <= (fat_file_size == FRAME_BYTES_RGB666) ||
                                     (fat_file_size == FRAME_BYTES_RGB565);
                    format_rgb666 <= (fat_file_size == FRAME_BYTES_RGB666);
                    format_rgb565 <= (fat_file_size == FRAME_BYTES_RGB565);
                    if ((fat_file_size != FRAME_BYTES_RGB666) &&
                        (fat_file_size != FRAME_BYTES_RGB565))
                        loader_error <= 1'b1;
                end

                if (fat_out_valid && size_ok &&
                    (write_pixel_count < FRAME_PIXELS)) begin
                    if (format_rgb666) begin
                        if (bit_count_plus_8 >= 6'd18) begin
                            fb_wr_addr        <= write_pixel_count;
                            // RGB666 -> RGB565: keep the most significant
                            // five R/B bits and all six G bits. Spatial detail
                            // is unchanged; only two low color bits are dropped.
                            fb_wr_data        <= {
                                bit_buffer_with_byte[17:13],
                                bit_buffer_with_byte[11:6],
                                bit_buffer_with_byte[5:1]
                            };
                            fb_wr_en          <= 1'b1;
                            write_pixel_count <= write_pixel_count + 1'b1;
                            bit_buffer        <= bit_buffer_with_byte >> 18;
                            bit_count         <= bit_count_plus_8 - 6'd18;
                        end else begin
                            bit_buffer <= bit_buffer_with_byte;
                            bit_count  <= bit_count_plus_8;
                        end
                    end else if (format_rgb565) begin
                        if (!byte_phase) begin
                            pixel_low_byte <= fat_out_byte;
                            byte_phase     <= 1'b1;
                        end else begin
                            // Legacy RGB565 is already in framebuffer format.
                            fb_wr_addr <= write_pixel_count;
                            fb_wr_data <= {fat_out_byte, pixel_low_byte};
                            fb_wr_en          <= 1'b1;
                            write_pixel_count <= write_pixel_count + 1'b1;
                            byte_phase        <= 1'b0;
                        end
                    end
                end

                // EOF is asserted after the final sector transaction, so the
                // final framebuffer write has already completed by this point.
                if (fat_eof && !frame_ready_sys) begin
                    if (size_ok && (write_pixel_count == FRAME_PIXELS) &&
                        stream_aligned) begin
                        frame_ready_sys <= 1'b1;
                    end else begin
                        loader_error <= 1'b1;
                    end
                end

                if ((fat_error_code != 8'h00) ||
                    (sd_error_code != 8'h00)) begin
                    loader_error    <= 1'b1;
                    frame_ready_sys <= 1'b0;
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // Full-frame dual-clock RGB565 framebuffer.
    // ---------------------------------------------------------------------
    wire [10:0] lcd_x;
    wire [9:0]  lcd_y;
    wire        lcd_active;
    wire        lcd_hsync_raw;
    wire        lcd_vsync_raw;
    wire        lcd_frame_start;

    lcd_timing_1024x600_image u_timing (
        .pix_clk(lcd_pix_clk), .rst_n(lcd_logic_rst_n),
        .x(lcd_x), .y(lcd_y), .active_video(lcd_active),
        .hsync(lcd_hsync_raw), .vsync(lcd_vsync_raw),
        .frame_start(lcd_frame_start)
    );

    // The BRAM has one registered read cycle. During active video request the
    // NEXT pixel, while horizontal blanking continuously preloads pixel 0 of
    // the current line. This lets the final LCD RGB/DE register use the same
    // timing style as the verified Game project without an extra DE pipeline.
    wire [19:0] lcd_line_base = {lcd_y, 10'b0};
    wire [19:0] fb_rd_addr =
        (lcd_active && (lcd_x < 11'd1023)) ?
            (lcd_line_base + lcd_x + 20'd1) :
            lcd_line_base;
    wire [15:0] fb_rd_data;

    // Original proven 16-bit dual-clock BRAM organization.
    rgb565_framebuffer_dp #(
        .FRAME_PIXELS(FRAME_PIXELS), .ADDR_W(FB_ADDR_W)
    ) u_framebuffer (
        .wr_clk(sys_clk), .wr_en(fb_wr_en), .wr_addr(fb_wr_addr),
        .wr_data(fb_wr_data),
        .rd_clk(lcd_pix_clk), .rd_addr(fb_rd_addr), .rd_data(fb_rd_data)
    );

    // ---------------------------------------------------------------------
    // LCD-domain frame control.
    // Blank and reveal transitions happen only at frame_start.
    // ---------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [2:0] frame_ready_sync;
    (* ASYNC_REG = "TRUE" *) reg [2:0] blank_request_sync;
    (* ASYNC_REG = "TRUE" *) reg [2:0] load_error_sync;
    reg display_enable;

    wire load_error_sys = loader_error || (sd_error_code != 8'h00) ||
                          (fat_error_code != 8'h00);

    always @(posedge lcd_pix_clk or negedge lcd_logic_rst_n) begin
        if (!lcd_logic_rst_n) begin
            frame_ready_sync   <= 3'b000;
            blank_request_sync <= 3'b000;
            load_error_sync    <= 3'b000;
        end else begin
            frame_ready_sync   <= {frame_ready_sync[1:0], frame_ready_sys};
            blank_request_sync <= {blank_request_sync[1:0], blank_request_sys};
            load_error_sync    <= {load_error_sync[1:0], load_error_sys};
        end
    end

    always @(posedge lcd_pix_clk or negedge lcd_logic_rst_n) begin
        if (!lcd_logic_rst_n) begin
            display_enable <= 1'b0;
            blank_ack_lcd  <= 1'b0;
        end else if (lcd_frame_start) begin
            if (blank_request_sync[2]) begin
                display_enable <= 1'b0;
                blank_ack_lcd  <= 1'b1;
            end else begin
                blank_ack_lcd <= 1'b0;
                if (frame_ready_sync[2])
                    display_enable <= 1'b1;
                else
                    display_enable <= 1'b0;
            end
        end
    end

    // RGB565 -> RGB888 by standard bit replication. This changes color depth
    // only; it does not rescale or filter pixels.
    wire [4:0] r5 = fb_rd_data[15:11];
    wire [5:0] g6 = fb_rd_data[10:5];
    wire [4:0] b5 = fb_rd_data[4:0];
    wire [7:0] rgb_r = {r5, r5[4:2]};
    wire [7:0] rgb_g = {g6, g6[5:4]};
    wire [7:0] rgb_b = {b5, b5[4:2]};

    // Match the verified Game project's LCD output pipeline: one final RGB/DE
    // register clocked by lcd_pix_clk, with HSYNC/VSYNC coming directly from
    // the timing generator. No forced IOB placement and no extra DE delay.
    reg [23:0] lcd_rgb_reg;
    reg        lcd_de_reg;
    always @(posedge lcd_pix_clk or negedge lcd_logic_rst_n) begin
        if (!lcd_logic_rst_n) begin
            lcd_rgb_reg <= 24'h000000;
            lcd_de_reg  <= 1'b0;
        end else begin
            lcd_de_reg <= lcd_active;
            if (lcd_active) begin
                if (display_enable)
                    lcd_rgb_reg <= {rgb_r, rgb_g, rgb_b};
                else if (load_error_sync[2])
                    lcd_rgb_reg <= 24'h400000;
                else
                    lcd_rgb_reg <= 24'h101820;
            end else begin
                lcd_rgb_reg <= 24'h000000;
            end
        end
    end

    assign LCD_R     = lcd_rgb_reg[23:16];
    assign LCD_G     = lcd_rgb_reg[15:8];
    assign LCD_B     = lcd_rgb_reg[7:0];
    assign LCD_DE    = lcd_de_reg;
    assign LCD_HSYNC = lcd_hsync_raw;
    assign LCD_VSYNC = lcd_vsync_raw;

    // Preserve the exact verified LCD clock output phase from the Game project.
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) u_lcd_clk_oddr (
        .Q(LCD_CLK), .C(lcd_pix_clk), .CE(1'b1),
        .D1(1'b0), .D2(1'b1), .R(~lcd_logic_rst_n), .S(1'b0)
    );

    assign LCD_BL   = 1'b1;
    assign LCD_nRST = 1'b1;

    // LEDs, active-high yellow:
    // [4] LCD MMCM locked
    // [3] SD initialized successfully
    // [2] complete frame ready/displayable
    // [1] any SD/FAT/size/load error
    // [0] FAT image stream is active
    assign led[4] = lcd_clk_locked;
    assign led[3] = sd_init_ok;
    assign led[2] = frame_ready_sys;
    assign led[1] = loader_error || (sd_error_code != 8'h00) ||
                    (fat_error_code != 8'h00);
    assign led[0] = fat_playing;

    wire _unused_ok = &{1'b0, sd_init_done, sd_card_sdhc,
                         fat_bytes_sent[0], blank_ack_sync[0]};
endmodule

`default_nettype wire
