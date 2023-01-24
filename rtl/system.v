/*============================================================================
	FPGA implementation of BBC Bridge Companion - main system module

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

`timescale 1ns / 1ns

module system (
	input clk,
	input ce_10m7,
	input ce_5m3,
	input ce_vid,
	input reset /*verilator public_flat*/,
	input [11:0] inputs,
	output [23:0] rgb,
	output vsync,
	output hsync,
	output vblank,
	output hblank,

	input [3:0] cartridge_select,

	input [15:0] dn_addr,
	input 		 dn_wr,
	input [7:0]  dn_index,
	input [7:0]  dn_data
);

// Overloaded reset signal to enable 'hot-swap' of carts
reg reset_active;
always @(posedge clk)
begin
	if(reset || cartridge_loading > 4'b0 || custom_cart_write) 
	begin
		reset_active <= 1'b1;
	end
	else
	begin
		if(ce_vid)
		begin
			reset_active <= 1'b0;
		end
	end

end

// IC1 - Address decoding
// - Address decoding is handled by a PAL IC which is not dumped so this is derived from the MAME memory map
// CPU ROM
wire rom_cs = cpu_addr[15:14] == 2'b0;
wire rom_read/*verilator public_flat*/;
assign rom_read = rom_cs & ~cpu_rd_n;
// CPU RAM
wire ram_cs = cpu_addr >= 16'hE000 && ~cpu_mreq_n;
wire ram_read = ram_cs & ~cpu_rd_n;
wire ram_write = ram_cs & ~cpu_wr_n;
// Z80 PIO
wire pio_cs = ~cpu_addr[7] && ~cpu_iorq_n;
wire pio_read = pio_cs & ~cpu_rd_n;
wire pio_write = pio_cs & ~cpu_wr_n;
// VDP
wire vdp_cs = cpu_addr[7] && ~cpu_iorq_n;
wire vdp_read = vdp_cs & ~cpu_rd_n;
wire vdp_write = vdp_cs & ~cpu_wr_n;
// Memory card/cartridge
wire cartridge_cs = cpu_addr >= 16'h4000 && cpu_addr < 16'hC000;
wire cartridge_read = cartridge_cs & ~cpu_rd_n;
wire custom_cart_write = dn_wr && dn_index == 8'd1;

// IC2 - CPU RAM
// - Two options on schematic - 2Kb or 8Kb.  Providing 8Kb here despite none of the offical carts using it!
wire [7:0] ram_data_out;
spram #(13,8) ram 
(
	.clock(clk),
	.address(cpu_addr[12:0]),
	.wren(ram_write),
	.data(cpu_data_out),
	.q(ram_data_out)
);

// IC3/4 - ROM
// - 2x 8Kb PROMs
// - Firmware is baked into ROM, but left as DPRAM to allow custom firmware load via OSD
wire [7:0] pgrom_data_out;
wire pgrom_wr = (dn_addr[15:14] == 2'b0) && dn_wr && dn_index == 8'd0;
dpram #(14,8,"roms/bios.hex") pgrom
(
	.clock_a(clk),
	.address_a(cpu_addr[13:0]),
	.enable_a(1'b1),
	.wren_a(1'b0),
	.data_a(),
	.q_a(pgrom_data_out),

	.clock_b(clk),
	.address_b(dn_addr[13:0]),
	.enable_b(pgrom_wr),
	.wren_b(pgrom_wr),
	.data_b(dn_data),
	.q_b()
);

// IC5 - Z80 CPU
wire cpu_mreq_n;
wire cpu_iorq_n;
wire cpu_rd_n;
wire cpu_wr_n;
wire cpu_m1_n;
wire [15:0] cpu_addr;
wire [7:0] cpu_data_in;
wire [7:0] cpu_data_out;
tv80e cpu (
	.clk(clk),
	.cen(vdp_cpu_clk),
	.reset_n(~reset_active),
	.wait_n(1'b1),
	.int_n(vdp_int_n),
	.nmi_n(1'b1),
	.busrq_n(1'b1),
	.m1_n(cpu_m1_n),
	.mreq_n(cpu_mreq_n),
	.iorq_n(cpu_iorq_n),
	.rd_n(cpu_rd_n),
	.wr_n(cpu_wr_n),
	.rfsh_n(),
	.halt_n(),
	.busak_n(),
	.A(cpu_addr),
	.di(cpu_data_in),
	.dout(cpu_data_out)
);

wire [7:0] mem_data_out = rom_read ? pgrom_data_out : 
						ram_read ? ram_data_out :
						cartridge_read ? cartridge_data_out : 
						8'h0;
wire [7:0] io_data_out = pio_read ? pio_data_out : 
						vdp_read ? vdp_data_out : 
						8'h0;

assign cpu_data_in = !cpu_mreq_n ? mem_data_out : io_data_out;

// IC6 - Z80 PIO
wire pio_int_n;
wire [7:0] pio_data_out;
wire [7:0] pio_port_a;
reg [7:0] pio_port_b;
wire pio_basel = cpu_addr[5];
wire pio_cdsel = cpu_addr[6];
z8420 pio (
	.RST_n(~reset_active),
	.CLK(clk),
	.ENA(vdp_cpu_clk),
	.BASEL(pio_basel),
	.CDSEL(pio_cdsel),
	.CE(~pio_cs),
	.RD_n(cpu_rd_n),
	.WR_n(cpu_wr_n),
	.IORQ_n(cpu_iorq_n),
	.M1_n(cpu_m1_n),
	.DI(cpu_data_out),
	.DO(pio_data_out),
	.IEI(1'b1),
	.IEO(),
	.INT_n(),
	.A(pio_port_a),
	.B(pio_port_b)
);
// These PIO signals are unused
// wire pio_pa0 = pio_port_a[0];
// wire pio_pa1 = pio_port_a[1];
// wire pio_msl0 = pio_port_a[5];
// wire pio_msl1 = pio_port_a[6];
// wire pio_page = pio_port_a[7];

// Latch expected inputs based on PIO writes - without any schematics for the keypad part this is the best I can do!
always @(posedge clk)
begin
	if(pio_write)
	begin
		if(cpu_data_out == 8'hEF) pio_port_b[3:0] <= inputs[3:0];
		if(cpu_data_out == 8'hDF) pio_port_b[3:0] <= inputs[7:4];
		if(cpu_data_out == 8'hBF) pio_port_b[3:0] <= inputs[11:8];
	end
end


// IC7 - VDP - TMS9129
wire vdp_int_n;
wire [7:0] vdp_data_out;
wire [3:0] vdp_col;
wire [7:0] vdp_r;
wire [7:0] vdp_g;
wire [7:0] vdp_b;
wire vdp_hsync_n;
wire vdp_vsync_n;
wire vdp_csync_n;
wire vdp_blank_n;
wire vdp_hblank;
wire vdp_vblank;
wire vdp_cpu_clk;
vdp18_core #(
	.is_pal_g(1'b1),
	.compat_rgb_g(1'b0)
) vdp (
	.clk_i(clk),
	.clk_en_10m7_i(ce_10m7),
	.clk_en_3m58_o(vdp_cpu_clk),
	.reset_n_i(~reset_active),
	.csr_n_i(~vdp_read),
	.csw_n_i(~vdp_write),
	.mode_i(cpu_addr[0]),
	.int_n_o(vdp_int_n),
	.cd_i(cpu_data_out),
	.cd_o(vdp_data_out),
	.vram_we_o(vram_we),
	.vram_a_o(vram_addr),
	.vram_d_o(vram_data_in),
	.vram_d_i(vram_data_out),
	.border_i(1'b1),
	.col_o(vdp_col),
	.rgb_r_o(vdp_r),
	.rgb_g_o(vdp_g),
	.rgb_b_o(vdp_b),
	.hsync_n_o(vdp_hsync_n),
	.vsync_n_o(vdp_vsync_n),
	.blank_n_o(vdp_blank_n),
	.hblank_o(vdp_hblank),
	.vblank_o(vdp_vblank),
	.comp_sync_n_o(vdp_csync_n)
);

assign hsync = ~vdp_hsync_n;
assign vsync = ~vdp_vsync_n;
assign hblank = vdp_hblank;
assign vblank = vdp_vblank;
assign rgb = { vdp_b, vdp_g, vdp_r };

// IC8/9 - VRAM
wire [13:0] vram_addr;
wire [7:0] vram_data_out;
wire [7:0] vram_data_in;
wire vram_we;
spram #(14,8) vram 
(
	.clock(clk),
	.address(vram_addr),
	.wren(vram_we),
	.data(vram_data_in),
	.q(vram_data_out)
);

// Cartridge / memory cards
// - cartridge_select controls whether re-programmable memory card (for loading custom binaries from OSD) is used, or one of the built-in cartridge ROMS
wire [15:0] cartridge_addr = (cpu_addr - 16'h4000);
wire [7:0] cartridge_data_out = cartridge_select == CART_ADVANCEDBIDDING ? cart_advbidng_data_out :
								 cartridge_select == CART_ADVANCEDDEFENCE ? cart_advdefnc_data_out :
								 cartridge_select == CART_BRIDGEBUILDER ? cart_bbuilder_data_out :
								 cartridge_select == CART_CONVENTIONS1 ? cart_convent1_data_out :
								 cartridge_select == CART_CLUBPLAY1 ? cart_cplay1_data_out :
								 cartridge_select == CART_CLUBPLAY2 ? cart_cplay2_data_out :
								 cartridge_select == CART_CLUBPLAY3 ? cart_cplay3_data_out :
								 cartridge_select == CART_DUPLICATE1 ? cart_duplict1_data_out :
								 cartridge_select == CART_MASTERPLAY1 ? cart_mplay1_data_out :
								 custom_cart_data_out;
reg [3:0] cartridge_current = 4'b1111;
reg [3:0] cartridge_loading;

always @(posedge clk)
begin
	if(cartridge_current != cartridge_select)
	begin
		cartridge_loading <= 4'b1111;
		cartridge_current <= cartridge_select;
	end
	if(cartridge_loading > 4'b0) cartridge_loading <= cartridge_loading - 4'b1;
end

// Built-in cartridge IDs
localparam [3:0] CART_ADVANCEDBIDDING = 4'd1;
localparam [3:0] CART_ADVANCEDDEFENCE = 4'd2;
localparam [3:0] CART_BRIDGEBUILDER = 4'd3;
localparam [3:0] CART_CONVENTIONS1 = 4'd4;
localparam [3:0] CART_CLUBPLAY1 = 4'd5;
localparam [3:0] CART_CLUBPLAY2 = 4'd6;
localparam [3:0] CART_CLUBPLAY3 = 4'd7;
localparam [3:0] CART_DUPLICATE1 = 4'd8;
localparam [3:0] CART_MASTERPLAY1 = 4'd9;

// Custom cartridge DPRAM instance
wire [7:0] custom_cart_data_out;
dpram #(15,8) custom_cart 
(
	.clock_a(clk),
	.address_a(cartridge_addr[14:0]),
	.enable_a(1'b1),
	.wren_a(1'b0),
	.data_a(),
	.q_a(custom_cart_data_out),

	.clock_b(clk),
	.address_b(dn_addr[14:0]),
	.enable_b(custom_cart_write),
	.wren_b(custom_cart_write),
	.data_b(dn_data),
	.q_b()
);

// Built-in cartridge ROMs
wire [7:0] cart_advbidng_data_out;
sprom #(15,8,"roms/advbidng.hex") cart_advbigng
(
	.clock(clk),
	.address(cartridge_addr[14:0]),
	.q(cart_advbidng_data_out)
);
wire [7:0] cart_advdefnc_data_out;
sprom #(15,8,"roms/advdefnc.hex") cart_advdefnc
(
	.clock(clk),
	.address(cartridge_addr[14:0]),
	.q(cart_advdefnc_data_out)
);
wire [7:0] cart_bbuilder_data_out;
sprom #(15,8,"roms/bbuilder.hex") cart_bbuilder
(
	.clock(clk),
	.address(cartridge_addr[14:0]),
	.q(cart_bbuilder_data_out)
);
wire [7:0] cart_convent1_data_out;
sprom #(15,8,"roms/convent1.hex") cart_convent1
(
	.clock(clk),
	.address(cartridge_addr[14:0]),
	.q(cart_convent1_data_out)
);
wire [7:0] cart_cplay1_data_out;
sprom #(15,8,"roms/cplay1.hex") cart_cplay1
(
	.clock(clk),
	.address(cartridge_addr[14:0]),
	.q(cart_cplay1_data_out)
);
wire [7:0] cart_cplay2_data_out;
sprom #(15,8,"roms/cplay2.hex") cart_cplay2
(
	.clock(clk),
	.address(cartridge_addr[14:0]),
	.q(cart_cplay2_data_out)
);
wire [7:0] cart_cplay3_data_out;
sprom #(15,8,"roms/cplay3.hex") cart_cplay3
(
	.clock(clk),
	.address(cartridge_addr[14:0]),
	.q(cart_cplay3_data_out)
);
wire [7:0] cart_duplict1_data_out;
sprom #(15,8,"roms/duplict1.hex") cart_duplict1
(
	.clock(clk),
	.address(cartridge_addr[14:0]),
	.q(cart_duplict1_data_out)
);
wire [7:0] cart_mplay1_data_out;
sprom #(15,8,"roms/mplay1.hex") cart_mplay1
(
	.clock(clk),
	.address(cartridge_addr[14:0]),
	.q(cart_mplay1_data_out)
);

endmodule