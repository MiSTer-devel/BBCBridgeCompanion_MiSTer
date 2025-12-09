/*============================================================================
	FPGA implementation of BBC Bridge Companion system
	- Developed by BBC Enterprises Ltd and Unicard Ltd
	- Manufactured by Heber

	Copyright (C) 2022 - Jim Gregory - https://github.com/JimmyStones/

	This program is free software; you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the Free
	Software Foundation; either version 3 of the License, or (at your option)
	any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along
	with this program. If not, see <http://www.gnu.org/licenses/>.
===========================================================================*/

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign FB_FORCE_BLANK = 0;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1;
assign AUDIO_MIX = 0;
assign AUDIO_L = 0;
assign AUDIO_R = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign LED_USER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[9:8];

assign VIDEO_ARX = (!ar) ? 8'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 8'd3 : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"BBCBridgeCompanion;;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"O89,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"OAD,Cartridge,Empty,Advanced Bidding,Advanced Defence,Bridge Builder,Conventions 1,Club Play 1,Club Play 2,Club Play 3,Duplicate 1,Master Play 1;",
	"-;",
	"F0,BIN,Load BIOS;",
	"F1,BIN,Load custom cartridge;",
	"-;",
	"R0,Reset;",
	"J1,Pass,NT,Dbl,Rdbl,Start,Back,Play/Yes,Play/No",
	"Jn,X,Y,A,B,R,L,Z,C;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;
wire clk_vid = clk_sys;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys)
);

////////////////////   HPS   /////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;
wire [21:0] gamma_bus;

wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_index;
wire [10:0] ps2_key;
wire [15:0] joystick_0, joystick_1;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),

	.buttons(buttons),
	.status(status),
	.status_menumask(),

	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);

reg ce_10m7;
reg ce_5m3;
reg ce_vid;
wire ce_pix = ce_5m3;
always @(posedge clk_sys)
begin
	reg [2:0] div;
	div <= div + 3'd1;
	ce_10m7 = div[1:0] == 2'b0;
	ce_5m3 = div[2:0] == 3'b0;
	ce_vid = div[2:0] == 3'b111;
end

///////////////////         Keyboard           //////////////////

reg btn_pass      = 0;
reg btn_spades    = 0;
reg btn_clubs     = 0;
reg btn_rdbl      = 0;
reg btn_NT        = 0;
reg btn_hearts_up = 0;
reg btn_play_yes  = 0;
reg btn_back      = 0;
reg btn_dbl       = 0;
reg btn_diamonds_down = 0;
reg btn_start = 0;
reg btn_play_no = 0;

wire pressed = ps2_key[9];
wire [7:0] code = ps2_key[7:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	if(old_state != ps2_key[10]) begin
		case(code)
			'h1C: btn_pass			<= pressed; // A
			'h1A: btn_spades		<= pressed; // Z
			'h2A: btn_clubs			<= pressed; // V
			'h2B: btn_rdbl			<= pressed; // F
			'h1B: btn_NT			<= pressed; // S
			'h22: btn_hearts_up		<= pressed; // X
			'h14: btn_play_yes		<= pressed; // left contrl
			'h66: btn_back			<= pressed; // backspace
			'h23: btn_dbl			<= pressed; // D
			'h21: btn_diamonds_down	<= pressed; // C
			'h16: btn_start			<= pressed; // 1
			'h11: btn_play_no		<= pressed; // left alt
		endcase
	end
end

wire [11:0] inputs = {
	btn_play_no | joystick_0[10], // Keyboard Left Alt / Joystick Button 8 (default C)
	btn_start | joystick_0[8], // Keyboard 1 / Joystick Button 5 (default R)
	btn_diamonds_down | joystick_0[2], // Keyboard C / Joystick Down,
	btn_dbl | joystick_0[6], // Keyboard D / Joystick Button 3 (default A)
	btn_back | joystick_0[9], // Keyboard Backspace / Joystick Button 6 (default L)
	btn_play_yes | joystick_0[8], // Keyboard Left Control / Joystick Button 7 (default Z)
	btn_hearts_up | joystick_0[3], // Keyboard X / Joystick Up,
	btn_NT | joystick_0[5], // Keyboard S / Joystick Button 2 (default Y)
	btn_rdbl | joystick_0[7], // Keyboard F / Joystick Button 4 (default B)
	btn_clubs | joystick_0[0], // Keyboard V / Joystick Right
	btn_spades | joystick_0[1], // Keyboard Z / Joystick Left
	btn_pass | joystick_0[4] // Keyboard A / Joystick Button 1 (default X)
};

///////////////////   VIDEO   ////////////////////
wire [23:0] rgb;
wire hblank, vblank;
wire hs, vs;
wire rotate_ccw = 1;
wire no_rotate = 1'b1;
wire flip = ~no_rotate;
wire video_rotated;

screen_rotate screen_rotate (.*);

arcade_video #(256,24) arcade_video
(
	.*,
	.clk_video(clk_vid),
	.RGB_in({ rgb[7:0], rgb[15:8], rgb[23:16] }),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),
	.fx(status[5:3])
);

wire reset/*verilator public_flat*/;
assign reset = (RESET | status[0]); 

system system (
	.clk(clk_sys),
	.ce_10m7(ce_10m7),
	.ce_5m3(ce_5m3),
	.ce_vid(ce_vid),
	.reset(reset),
	.rgb(rgb),
	.inputs(inputs),
	.hsync(hs),
	.vsync(vs),
	.hblank(hblank),
	.vblank(vblank),
	.cartridge_select(status[13:10]),
	.dn_addr(ioctl_addr[15:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr),
	.dn_index(ioctl_index)
);

endmodule