/*============================================================================
	BBC Bridge Companion for MiSTer FPGA - Verilator simulation top

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

`timescale 1 ps / 1 ps

module emu(

	input clk_sys /*verilator public_flat*/,
	input RESET /*verilator public_flat*/,
	input [11:0]  inputs/*verilator public_flat*/,

	output [7:0] VGA_R/*verilator public_flat*/,
	output [7:0] VGA_G/*verilator public_flat*/,
	output [7:0] VGA_B/*verilator public_flat*/,
	
	output VGA_HS,
	output VGA_VS,
	output VGA_HB,
	output VGA_VB,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,

	input        ioctl_download,
	input        ioctl_upload,
	input        ioctl_wr,
	input [24:0] ioctl_addr,
	input [7:0]  ioctl_dout,
	input [7:0]  ioctl_din,
	input [7:0]  ioctl_index,
	output  reg  ioctl_wait = 1'b0

);

	// Convert video output to 8bpp RGB
	wire [23:0] rgb;
	assign VGA_R = rgb[7:0];
	assign VGA_G = rgb[15:8];
	assign VGA_B = rgb[23:16];

	reg ce_10m7 /*verilator public_flat*/;
	reg ce_5m3 /*verilator public_flat*/;
	reg ce_vid;
	wire ce_pix /*verilator public_flat*/;
	assign ce_pix = ce_5m3;

	always @(posedge clk_sys)
	begin
		reg [2:0] div;
		div <= div+1'd1;
		ce_10m7 = div[1:0] == 2'b0;
		ce_5m3 = div[2:0] == 3'b0;
		ce_vid = div[2:0] == 3'b111;
	end

	wire rom_download = ioctl_download && ioctl_index == 8'b0;
	wire reset/*verilator public_flat*/;
	assign reset = (RESET | rom_download); 

	reg [3:0] cartridge_select/*verilator public_flat*/;
	
	system system (
		.clk(clk_sys),
		.ce_10m7(ce_10m7),
		.ce_5m3(ce_5m3),
		.ce_vid(ce_vid),
		.reset(reset),
		.rgb(rgb),
		.inputs(~inputs),
		.hsync(VGA_HS),
		.vsync(VGA_VS),
		.hblank(VGA_HB),
		.vblank(VGA_VB),
		.cartridge_select(cartridge_select),
		.dn_addr(ioctl_addr[15:0]),
		.dn_data(ioctl_dout),
		.dn_index(ioctl_index),
		.dn_wr(ioctl_wr)
	);

endmodule
