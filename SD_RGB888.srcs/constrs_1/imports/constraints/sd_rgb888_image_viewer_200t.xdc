###############################################################################
# GX-BIDT + XC7A200T-FBG484-2
# SD-card 1024x600 RGB888 image viewer
# Top: top_sd_rgb888_image_viewer
###############################################################################

# 50 MHz system clock (same as verified Game project)
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports sys_clk]
create_clock -name sys_clk -period 20.000 [get_ports sys_clk]

# Five-way keys: UP / LEFT / RIGHT / DOWN / CENTER
set_property -dict {PACKAGE_PIN V17  IOSTANDARD LVCMOS33 PULLUP true} [get_ports S1_KEYA]
set_property -dict {PACKAGE_PIN W17  IOSTANDARD LVCMOS33 PULLUP true} [get_ports S1_KEYB]
set_property -dict {PACKAGE_PIN U17  IOSTANDARD LVCMOS33 PULLUP true} [get_ports S1_KEYC]
set_property -dict {PACKAGE_PIN U18  IOSTANDARD LVCMOS33 PULLUP true} [get_ports S1_KEYD]
set_property -dict {PACKAGE_PIN AA18 IOSTANDARD LVCMOS33 PULLUP true} [get_ports S1_KEYP]

# Core-board TF/SD card, SPI mode (verified previous audio project)
# DATA3/CS   B13_L4_N -> AB15
# CMD/MOSI   B13_L6_N -> Y14
# CLK        B13_L6_P -> W14
# DATA0/MISO B13_L1_P -> Y16
# Card-detect is intentionally not used.
set_property -dict {PACKAGE_PIN AB15 IOSTANDARD LVCMOS33} [get_ports SD_CS_N]
set_property -dict {PACKAGE_PIN Y14  IOSTANDARD LVCMOS33} [get_ports SD_MOSI]
set_property -dict {PACKAGE_PIN W14  IOSTANDARD LVCMOS33} [get_ports SD_SCLK]
set_property -dict {PACKAGE_PIN Y16  IOSTANDARD LVCMOS33 PULLUP true} [get_ports SD_MISO]

# LCD RGB888 - copied from verified Game project
set_property -dict {PACKAGE_PIN M17 IOSTANDARD LVCMOS33} [get_ports {LCD_R[0]}]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports {LCD_R[1]}]
set_property -dict {PACKAGE_PIN E21 IOSTANDARD LVCMOS33} [get_ports {LCD_R[2]}]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports {LCD_R[3]}]
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS33} [get_ports {LCD_R[4]}]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports {LCD_R[5]}]
set_property -dict {PACKAGE_PIN A13 IOSTANDARD LVCMOS33} [get_ports {LCD_R[6]}]
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS33} [get_ports {LCD_R[7]}]

set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33} [get_ports {LCD_G[0]}]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports {LCD_G[1]}]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports {LCD_G[2]}]
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33} [get_ports {LCD_G[3]}]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports {LCD_G[4]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {LCD_G[5]}]
set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVCMOS33} [get_ports {LCD_G[6]}]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD LVCMOS33} [get_ports {LCD_G[7]}]

set_property -dict {PACKAGE_PIN K21 IOSTANDARD LVCMOS33} [get_ports {LCD_B[0]}]
set_property -dict {PACKAGE_PIN L21 IOSTANDARD LVCMOS33} [get_ports {LCD_B[1]}]
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33} [get_ports {LCD_B[2]}]
set_property -dict {PACKAGE_PIN M22 IOSTANDARD LVCMOS33} [get_ports {LCD_B[3]}]
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33} [get_ports {LCD_B[4]}]
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports {LCD_B[5]}]
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33} [get_ports {LCD_B[6]}]
set_property -dict {PACKAGE_PIN N19 IOSTANDARD LVCMOS33} [get_ports {LCD_B[7]}]

set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports LCD_CLK]
set_property -dict {PACKAGE_PIN M16 IOSTANDARD LVCMOS33} [get_ports LCD_HSYNC]
set_property -dict {PACKAGE_PIN N20 IOSTANDARD LVCMOS33} [get_ports LCD_VSYNC]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports LCD_DE]
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports LCD_BL]
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33} [get_ports LCD_nRST]

set_property DRIVE 8 [get_ports {{LCD_R[*]} {LCD_G[*]} {LCD_B[*]} LCD_CLK LCD_HSYNC LCD_VSYNC LCD_DE LCD_BL LCD_nRST}]
set_property SLEW SLOW [get_ports {{LCD_R[*]} {LCD_G[*]} {LCD_B[*]} LCD_CLK LCD_HSYNC LCD_VSYNC LCD_DE LCD_BL LCD_nRST}]

# Five active-high yellow LEDs
set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN E22 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN F18 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN D21 IOSTANDARD LVCMOS33} [get_ports {led[4]}]

# Final LCD signal-integrity tuning:
# Keep RGB/data/control on SLOW slew as in the verified baseline, but use a
# faster edge on the 51.2 MHz pixel clock so the panel sees a cleaner sampling
# edge without increasing switching noise on the 24-bit data bus.
set_property DRIVE 8 [get_ports LCD_CLK]
set_property SLEW FAST [get_ports LCD_CLK]
