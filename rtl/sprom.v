/*============================================================================
	Generic single-port ROM module

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

module sprom # (
	parameter address_width = 8,
	parameter data_width = 8,
	parameter init_file= ""
)
(
	input 							clock,
	input [(address_width-1):0]		address,
	output reg [(data_width-1):0]	q
);

	localparam ramLength = (2**address_width);

	reg [(data_width-1):0] mem [ramLength-1:0];

	initial begin
		if (init_file>0) $readmemh(init_file, mem);
	end

	always @(posedge clock)
	begin
		q <= mem[address];
	end

endmodule
