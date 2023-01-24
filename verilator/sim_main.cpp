#include <verilated.h>
#include "Vemu.h"

#include "imgui.h"
#include "implot.h"
#ifndef _MSC_VER
#include <stdio.h>
#include <SDL.h>
#include <SDL_opengl.h>
#else
#define WIN32
#include <dinput.h>
#endif

#include "sim_console.h"
#include "sim_bus.h"
#include "sim_video.h"
#include "sim_audio.h"
#include "sim_input.h"
#include "sim_clock.h"

#include "../imgui/imgui_memory_editor.h"
//#include "../imgui/ImGuiFileDialog.h"

#define FMT_HEADER_ONLY
#include <fmt/core.h>

#include <iostream>
#include <sstream>
#include <fstream>
#include <iterator>
#include <string>
#include <iomanip>

using namespace std;

// Simulation control
// ------------------
int initialReset = 48;
bool run_enable = 1;
bool pause_game = 0;
int batchSize = 25000000 / 100;
bool single_step = 0;
bool multi_step = 0;
int multi_step_amount = 1024;

// Debug GUI 
// ---------
const char* windowTitle = "Verilator Sim: BBC Bridge Companion";
const char* windowTitle_Control = "Simulation control";
const char* windowTitle_DebugLog = "Debug log";
const char* windowTitle_Video = "VGA output";
const char* windowTitle_Audio = "Audio output";
bool showDebugLog = true;
DebugConsole console;
MemoryEditor mem_edit_8;
MemoryEditor mem_edit_16;

// HPS emulator
// ------------
SimBus bus(console);

// Input handling
// --------------
SimInput input_0(12, console);
const int input_pass = 0;
const int input_spades = 1;
const int input_clubs = 2;
const int input_rdbl = 3;
const int input_NT = 4;
const int input_hearts_up = 5;
const int input_play_yes = 6;
const int input_back = 7;
const int input_dbl = 8;
const int input_diamonds_down = 9;
const int input_start = 10;
const int input_play_no = 11;

// Verilog module
// --------------
Vemu* top = NULL;
vluint64_t main_time = 0; // Current simulation time.
double sc_time_stamp()
{ // Called by $time in Verilog.
	return main_time;
}

int clk_vid_freq = 15468480 * 2;
int clk_sys_freq = 15468480;
SimClock clk_vid(1);
SimClock clk_sys(1);

void resetSim()
{
	main_time = 0;
	top->RESET = 1;
	clk_vid.Reset();
	clk_sys.Reset();
}

// Video
// -----
#define VGA_ROTATE 0
#define VGA_WIDTH 320
#define VGA_HEIGHT 256
#define VGA_SCALE_X vga_scale
#define VGA_SCALE_Y vga_scale
SimVideo video(VGA_WIDTH, VGA_HEIGHT, VGA_ROTATE);
float vga_scale = 2.0;

// Audio
// -----	
#define DISABLE_AUDIO
#ifndef DISABLE_AUDIO
SimAudio audio(clk_sys_freq, true);
#endif

// MAME debug log
//#define CPU_DEBUG

#ifdef CPU_DEBUG
bool log_instructions = true;
bool stop_on_log_mismatch = true;

std::vector<std::string> log_mame;
std::vector<std::string> log_cpu;
long log_index;
unsigned int ins_count = 0;

// CPU debug
std::string tracefilename = "traces/bbcbc.tr";
bool cpu_sync;
bool cpu_sync_last;
std::vector<std::vector<std::string> > opcodes;
std::map<std::string, std::string> opcode_lookup;

bool writeLog(const char* line)
{
	// Write to cpu log
	log_cpu.push_back(line);

	// Compare with MAME log
	bool match = true;
	ins_count++;

	std::string c_line = std::string(line);
	std::string c = "%d > " + c_line + " ";

	unsigned char acc = top->emu__DOT__system__DOT__cpu__DOT__i_tv80_core__DOT__ACC;
	//c.append(fmt::format(" A={0:02X}", acc));

	if (log_index < log_mame.size()) {
		std::string m_line = log_mame.at(log_index);

		std::string m_line_lower = m_line.c_str();
		for (auto& c : m_line_lower) { c = tolower(c); }
		std::string c_line_lower = c_line.c_str();
		for (auto& c : c_line_lower) { c = tolower(c); }

		if (log_instructions) {
			console.AddLog(c.c_str(), ins_count);
		}
		if (stop_on_log_mismatch && m_line_lower != c_line_lower) {
			if (log_instructions) {
				std::string m = "MAME > " + m_line;
				console.AddLog(m.c_str());
			}
			console.AddLog("DIFF at %d", log_index);
			match = false;
			run_enable = 0;
		}
	}
	else {
		console.AddLog("MAME OUT");
		run_enable = 0;
	}
	log_index++;
	return match;
}

void loadOpcodes()
{
	std::string fileName = "z80_opcodes.csv";
	std::string                           header;
	std::ifstream                         reader(fileName);
	if (reader.is_open()) {
		std::string line, column, id;
		std::getline(reader, line);
		header = line;
		while (std::getline(reader, line)) {
			std::stringstream        ss(line);
			std::vector<std::string> columns;
			bool                     withQ = false;
			std::string              part{ "" };
			while (std::getline(ss, column, ',')) {
				auto pos = column.find("\"");
				if (pos < column.length()) {
					withQ = !withQ;
					part += column.substr(0, pos);
					column = column.substr(pos + 1, column.length());
				}
				if (!withQ) {
					column += part;
					columns.emplace_back(std::move(column));
					part = "";
				}
				else {
					part += column + ",";
				}
			}
			opcodes.push_back(columns);
			opcode_lookup[columns[0]] = columns[1];
		}
	}
};

std::string int_to_hex(unsigned char val)
{
	std::stringstream ss;
	ss << std::setfill('0') << std::setw(2) << std::hex << (val | 0);
	return ss.str();
}

std::string get_opcode(int ir, int ir_ext, int ir_superext)
{
	std::string hex = "0x";
	if (ir_superext > 0) {
		hex.append(int_to_hex(ir_superext));
	}
	if (ir_ext > 0) {
		hex.append(int_to_hex(ir_ext));
	}
	hex.append(int_to_hex(ir));
	if (opcode_lookup.find(hex) != opcode_lookup.end()) {
		return opcode_lookup[hex];
	}
	else
	{
		hex.append(" - MISSING OPCODE");
		return hex;
	}
}

bool hasEnding(std::string const& fullString, std::string const& ending) {
	if (fullString.length() >= ending.length()) {
		return (0 == fullString.compare(fullString.length() - ending.length(), ending.length(), ending));
	}
	else {
		return false;
	}
}

std::string last_log;

unsigned short last_pc;
unsigned short last_last_pc;
unsigned char last_mreq;

unsigned short active_pc;
unsigned char active_ir;
unsigned char active_ir_ext;
unsigned char active_ir_superext;
bool active_ir_valid = false;

const int ins_size = 48;
int ins_index = 0;
int ins_pc[ins_size];
int ins_in[ins_size];
int ins_ma[ins_size];
unsigned char active_ins = 0;
unsigned char last_acc;

bool rom_read_last;

#endif


int verilate()
{

	if (!Verilated::gotFinish())
	{

		// Assert reset during startup
		top->RESET = 0;
		if (main_time < initialReset) top->RESET = 1;
		if (*bus.ioctl_download) top->RESET = 1;

		console.main_time = main_time;

		// Clock dividers
		clk_vid.Tick();

		if (clk_vid.clk != clk_vid.old) {
			clk_sys.Tick();

			// Set system clock in core
			top->clk_sys = clk_sys.clk;

			// Simulate both edges of system clock
			if (clk_sys.clk != clk_sys.old) {
				if (clk_sys.clk) {
					input_0.BeforeEval();
					bus.BeforeEval();
				}
				top->eval();
				if (clk_sys.clk) { bus.AfterEval(); }
			}

			// Output pixels on rising edge of pixel clock
			if (clk_vid.IsFalling() && top->emu__DOT__ce_pix) {
				uint32_t colour = 0xFF000000 | top->VGA_B << 16 | top->VGA_G << 8 | top->VGA_R;
				video.Clock(top->VGA_HB, top->VGA_VB, top->VGA_HS, top->VGA_VS, colour);
			}

		}

#ifndef DISABLE_AUDIO
		if (clk_sys.IsRising())
		{
			audio.Clock(top->AUDIO_L, top->AUDIO_R);
		}
#endif


		if (clk_sys.IsRising()) {
#ifdef CPU_DEBUG
			if (!top->emu__DOT__system__DOT__reset && top->emu__DOT__ce_5m3) {


				unsigned short pc = top->emu__DOT__system__DOT__cpu__DOT__i_tv80_core__DOT__PC;

				unsigned char di = top->emu__DOT__system__DOT__cpu__DOT__i_tv80_core__DOT__di;
				unsigned short ad = top->emu__DOT__system__DOT__cpu__DOT__i_tv80_core__DOT__A;
				unsigned char ir = top->emu__DOT__system__DOT__cpu__DOT__i_tv80_core__DOT__IR;

				unsigned char acc = top->emu__DOT__system__DOT__cpu__DOT__i_tv80_core__DOT__ACC;
				unsigned char z = top->emu__DOT__system__DOT__cpu__DOT__i_tv80_core__DOT__flag_z;

				unsigned char phi = top->emu__DOT__system__DOT__cpu__DOT__cen;
				unsigned char mcycle = top->emu__DOT__system__DOT__cpu__DOT__mcycle;
				unsigned char mreq = top->emu__DOT__system__DOT__cpu__DOT__mreq_n;
				bool ir_changed = top->emu__DOT__system__DOT__cpu__DOT__i_tv80_core__DOT__ir_changed;

				bool rom_read = top->emu__DOT__system__DOT__rom_read;

				top->emu__DOT__system__DOT__cpu__DOT__i_tv80_core__DOT__ir_changed = 0;

				bool new_data = (mreq && !last_mreq && mcycle <= 4);
				bool rom_data = (!rom_read && rom_read_last);
				if ((rom_data) && !ir_changed) {
					std::string type = "NONE";
					if (new_data && !rom_data) { type = "NEW_ONLY"; }
					if (new_data && rom_data) { type = "BOTH_DATA"; }
					if (!new_data && rom_data) { type = "ROM_ONLY"; }
					std::string message = "%08d > ";
					message = message.append(type);
					message = message.append(" PC=%04x IR=%02x AD=%04x DI=%02x");
					//console.AddLog(message.c_str(), main_time, pc, ir, ad, di);
					ins_in[ins_index] = di;
					ins_index++;
					if (ins_index > ins_size - 1) { ins_index = 0; }
				}
				//console.AddLog("%08d PC=%04x IR=%02x AD=%04x DI=%02x ACC=%d Z=%d ND=%d IRC=%d", main_time, pc, ir, ad, di, acc, z, new_data, ir_changed);

				last_mreq = mreq;
				rom_read_last = rom_read;

				if (ir_changed) {
					//console.AddLog("%08d IR_CHANGED> PC=%04x IR=%02x AD=%04x DI=%02x ACC=%x z=%x", main_time, pc, ir, ad, di, acc, z);
					//console.AddLog("ACTIVE_IR: %x ACTIVE_PC: %x ACtIVE_IR_EXT: %x", active_ir, active_pc, active_ir_ext);

					if (active_ir_valid) {
						std::string opcode = get_opcode(active_ir, 0, 0);

						if (opcode.c_str() == "")
						{
							console.AddLog("No opcode found for %x", active_ir);
						}

						// Is this a compound opcode?
						size_t pos = opcode.find("****");
						if (pos != std::string::npos)
						{
							if (active_ir == 0xDD)
							{
								//								console.AddLog("SUPER! Compound opcode start: %s", opcode);
								active_ir_superext = active_ir;
							}
							else {
								//							console.AddLog("Compound opcode start: %s", opcode);
								active_ir_ext = active_ir;
							}
						}
						else {
							unsigned char data1 = ins_in[ins_index - 2];
							unsigned char data2 = ins_in[ins_index - 1];
							data1 = ins_in[0];
							data2 = ins_in[1];
							//std::string fmt = fmt::format("A={0:02X} ", last_acc);
							std::string fmt;
							fmt.append("%04X: ");
							std::string opcode = get_opcode(active_ir, active_ir_ext, active_ir_superext);

							size_t pos = opcode.find("&0000");
							if (pos != std::string::npos)
							{
								//data1 = ins_in[0];
								//data2 = ins_in[1];
								//console.AddLog("&0000 %d %x %x %x", ins_index, ins_in[0], ins_in[1], ins_in[2]);
								char buf[6];
								sprintf(buf, "$%02X%02X", data2, data1);
								opcode.replace(pos, 5, buf);
							}

							pos = opcode.find("&4546");
							if (pos != std::string::npos)
							{
								//console.AddLog("&4546 %d %x %x %x", ins_index, ins_in[0], ins_in[1], ins_in[2]);
								char buf[6];
								unsigned char active_data = (ins_index == 1 ? data1 : data2);
								unsigned short add = active_pc + +2;
								if (opcode.substr(0, 4) == "djnz") {
									add = active_pc + ((signed char)active_data) + 2;
								}
								if (opcode.substr(0, 4) == "jr  ") {
									add = active_pc + ((signed char)active_data) + 2;
								}
								sprintf(buf, "$%04X", add);
								opcode.replace(pos, 5, buf);
							}

							pos = opcode.find("&00");
							if (pos != std::string::npos)
							{
								//console.AddLog("&00 %d %x %x %x", ins_index, ins_in[0], ins_in[1], ins_in[2]);
								char buf[4];
								sprintf(buf, "$%02X", ins_in[0]);
								opcode.replace(pos, 3, buf);

								pos = opcode.find("&00");
								if (pos != std::string::npos)
								{
									sprintf(buf, "$%02X", ins_in[1]);
									opcode.replace(pos, 3, buf);
								}
							}

							fmt.append(opcode);
							char buf[1024];
							sprintf(buf, fmt.c_str(), active_pc);
							writeLog(buf);

							// Clear instruction cache
							ins_index = 0;
							for (int i = 0; i < ins_size; i++) {
								ins_in[i] = 0;
								ins_ma[i] = 0;
							}
							if (active_ir_ext != 0) {
								active_ir_ext = 0;
								//		console.AddLog("Compound opcode cleared");
							}
							if (active_ir_superext != 0) {
								active_ir_superext = 0;
								//		console.AddLog("SUPER! Compound opcode cleared");
							}

							active_pc = ad;
						}
						last_acc = acc;
					}
					//console.AddLog("Setting active last_last_pc=%x last_pc=%x pc=%x addr=%x", last_last_pc, last_pc, pc, ad);
					active_ir_valid = true;
					ins_index = 0;
					active_ir = ir;

					last_last_pc = last_pc;
					last_pc = pc;
				}
			}
#endif
			main_time++;
		}
		return 1;
	}

	// Stop verilating and cleanup
	top->final();
	delete top;
	exit(0);
	return 0;
}

int main(int argc, char** argv, char** env)
{
	// Create core and initialise
	top = new Vemu();
	Verilated::commandArgs(argc, argv);

#ifdef WIN32
	// Attach debug console to the verilated code
	//Verilated::console = console;
	Verilated::setDebug(&console);
#endif

#ifdef CPU_DEBUG
	// Load debug opcodes
	loadOpcodes();

	// Load debug trace
	std::string line;
	std::ifstream fin(tracefilename);
	while (getline(fin, line)) {
		log_mame.push_back(line);
	}
#endif

	// Attach bus
	bus.ioctl_addr = &top->ioctl_addr;
	bus.ioctl_index = &top->ioctl_index;
	bus.ioctl_wait = &top->ioctl_wait;
	bus.ioctl_download = &top->ioctl_download;
	//bus.ioctl_upload = &top->ioctl_upload;
	bus.ioctl_wr = &top->ioctl_wr;
	bus.ioctl_dout = &top->ioctl_dout;
	//bus.ioctl_din = &top->ioctl_din;
	//input.ps2_key = &top->ps2_key;

#ifndef DISABLE_AUDIO
	audio.Initialise();
#endif

	mem_edit_16.Cols = 32;

	// Set up input modules
	input_0.Initialise();
#ifdef WIN32
	input_0.SetMapping(input_pass, DIK_A);
	input_0.SetMapping(input_spades, DIK_Z);
	input_0.SetMapping(input_clubs, DIK_V);
	input_0.SetMapping(input_rdbl, DIK_F);
	input_0.SetMapping(input_NT, DIK_S);
	input_0.SetMapping(input_hearts_up, DIK_X);
	input_0.SetMapping(input_play_yes, DIK_LCONTROL);
	input_0.SetMapping(input_back, DIK_BACKSPACE);
	input_0.SetMapping(input_dbl, DIK_D);
	input_0.SetMapping(input_diamonds_down, DIK_C);
	input_0.SetMapping(input_start, DIK_1);
	input_0.SetMapping(input_play_no, DIK_LALT);
#else
	//input.SetMapping(input_p1_up, SDL_SCANCODE_UP);
	//input.SetMapping(input_p1_right, SDL_SCANCODE_RIGHT);
	//input.SetMapping(input_p1_down, SDL_SCANCODE_DOWN);
	//input.SetMapping(input_p1_left, SDL_SCANCODE_LEFT);
	//input.SetMapping(input_p2_up, SDL_SCANCODE_W);
	//input.SetMapping(input_p2_right, SDL_SCANCODE_D);
	//input.SetMapping(input_p2_down, SDL_SCANCODE_S);
	//input.SetMapping(input_p2_left, SDL_SCANCODE_A);
	//input.SetMapping(input_coin, SDL_SCANCODE_5);
	//input.SetMapping(input_start1, SDL_SCANCODE_1);
	//input.SetMapping(input_start2, SDL_SCANCODE_2);
	//input.SetMapping(input_fire1, SDL_SCANCODE_RCTRL);
	//input.SetMapping(input_fire2, SDL_SCANCODE_LCTRL);
	//input.SetMapping(input_fire3, SDL_SCANCODE_SPACE);

#endif

	// Stage ROMs
	/*bus.LoadMRA("../releases/" + mraFilename);*/
	//bus.QueueDownload("roms\\boot.rom", 0, false);
	/*bus.QueueDownload("roms\\bbuilder.bin", 1, true);*/
	//bus.QueueDownload("roms\\advdefnc.bin", 1, true);
	//bus.QueueDownload("roms\\cplay1.bin", 1, true);

	bus.QueueDownload("roms\\bbuilder.bin", 1, true);

	// Setup video output
	if (video.Initialise(windowTitle) == 1) { return 1; }

#ifdef WIN32
	MSG msg;
	ZeroMemory(&msg, sizeof(msg));
	while (msg.message != WM_QUIT)
	{
		if (PeekMessage(&msg, NULL, 0U, 0U, PM_REMOVE))
		{
			TranslateMessage(&msg);
			DispatchMessage(&msg);
			continue;
		}
#else
	bool done = false;
	while (!done)
	{
		SDL_Event event;
		while (SDL_PollEvent(&event))
		{
			ImGui_ImplSDL2_ProcessEvent(&event);
			if (event.type == SDL_QUIT)
				done = true;
		}
#endif
		video.StartFrame();

		input_0.Read();

		// Draw GUI
		// --------
		ImGui::NewFrame();

		// Simulation control window
		ImGui::Begin(windowTitle_Control);
		ImGui::SetWindowPos(windowTitle_Control, ImVec2(0, 0), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Control, ImVec2(500, 170), ImGuiCond_Once);
		if (ImGui::Button("Reset simulation")) { resetSim(); } ImGui::SameLine();
		if (ImGui::Button("Start running")) { run_enable = 1; } ImGui::SameLine();
		if (ImGui::Button("Stop running")) { run_enable = 0; } ImGui::SameLine();
		ImGui::Checkbox("RUN", &run_enable);
		//ImGui::PopItemWidth();
		ImGui::SliderInt("Run batch size", &batchSize, 1, 250000);
		if (single_step == 1) { single_step = 0; }
		if (ImGui::Button("Single Step")) { run_enable = 0; single_step = 1; }
		ImGui::SameLine();
		if (multi_step == 1) { multi_step = 0; }
		if (ImGui::Button("Multi Step")) { run_enable = 0; multi_step = 1; }
		//ImGui::SameLine();
		ImGui::SliderInt("Multi step amount", &multi_step_amount, 8, 1024);

#ifdef CPU_DEBUG
		ImGui::NewLine();
		ImGui::Checkbox("Log CPU instructions", &log_instructions);
		ImGui::Checkbox("Stop on MAME diff", &stop_on_log_mismatch);
#endif
		ImGui::End();

		ImGui::Begin("LOADER");
		if (ImGui::Button("Alpha!?")) {
			top->emu__DOT__cartridge_select = 0;
			bus.QueueDownload("roms\\alpha.bin", 1, true);
		}
		if (ImGui::Button("Burger!?")) {
			top->emu__DOT__cartridge_select = 0;
			bus.QueueDownload("roms\\burger.bin", 1, true);
		}

		if (ImGui::Button("Advanced Bidding")) { top->emu__DOT__cartridge_select = 1; }
		if (ImGui::Button("Advanced Defence")) { top->emu__DOT__cartridge_select = 2; }
		if (ImGui::Button("Bridge Builder")) { top->emu__DOT__cartridge_select = 3; }

		ImGui::End();

		// Debug log window
		console.Draw(windowTitle_DebugLog, &showDebugLog, ImVec2(500, 700));
		ImGui::SetWindowPos(windowTitle_DebugLog, ImVec2(0, 160), ImGuiCond_Once);

		// Memory debug
		//ImGui::Begin("PGROM");
		//mem_edit_8.DrawContents(&top->emu__DOT__system__DOT__pgrom__DOT__mem, 32768, 0);
		//ImGui::End(); 
		ImGui::Begin("RAM");
		mem_edit_16.DrawContents(&top->emu__DOT__system__DOT__ram__DOT__mem, 4096, 0);
		ImGui::End();
		//ImGui::Begin("VRAM");
		//mem_edit_16.DrawContents(&top->emu__DOT__system__DOT__vram__DOT__mem, 16384, 0);
		//ImGui::End();
		//ImGui::Begin("CUSTOM_CART");
		//mem_edit_16.DrawContents(&top->emu__DOT__system__DOT__custom_cart__DOT__mem, 32768, 0);
		//ImGui::End();

		int windowX = 550;
		int windowWidth = (VGA_WIDTH * VGA_SCALE_X) + 24;
		int windowHeight = (VGA_HEIGHT * VGA_SCALE_Y) + 90;

		// Video window
		ImGui::Begin(windowTitle_Video);
		ImGui::SetWindowPos(windowTitle_Video, ImVec2(windowX, 0), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Video, ImVec2(windowWidth, windowHeight), ImGuiCond_Once);

		ImGui::SetNextItemWidth(400);
		ImGui::SliderFloat("Zoom", &vga_scale, 1, 8); ImGui::SameLine();
		ImGui::SetNextItemWidth(200);
		ImGui::SliderInt("Rotate", &video.output_rotate, -1, 1); ImGui::SameLine();
		ImGui::Checkbox("Flip V", &video.output_vflip);
		ImGui::Text("main_time: %d frame_count: %d sim FPS: %f", main_time, video.count_frame, video.stats_fps);

		// Draw VGA output
		ImGui::Image(video.texture_id, ImVec2(video.output_width * VGA_SCALE_X, video.output_height * VGA_SCALE_Y));
		ImGui::End();


#ifndef DISABLE_AUDIO

		ImGui::Begin(windowTitle_Audio);
		ImGui::SetWindowPos(windowTitle_Audio, ImVec2(windowX, windowHeight), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Audio, ImVec2(windowWidth, 250), ImGuiCond_Once);
		if (run_enable) {
			audio.CollectDebug((signed short)top->AUDIO_L, (signed short)top->AUDIO_R);
		}
		int channelWidth = (windowWidth / 2) - 16;
		ImPlot::CreateContext();
		if (ImPlot::BeginPlot("Audio - L", ImVec2(channelWidth, 220), ImPlotFlags_NoLegend | ImPlotFlags_NoMenus | ImPlotFlags_NoTitle)) {
			ImPlot::SetupAxes("T", "A", ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks, ImPlotAxisFlags_AutoFit | ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks);
			ImPlot::SetupAxesLimits(0, 1, -1, 1, ImPlotCond_Once);
			ImPlot::PlotStairs("", audio.debug_positions, audio.debug_wave_l, audio.debug_max_samples, audio.debug_pos);
			ImPlot::EndPlot();
		}
		ImGui::SameLine();
		if (ImPlot::BeginPlot("Audio - R", ImVec2(channelWidth, 220), ImPlotFlags_NoLegend | ImPlotFlags_NoMenus | ImPlotFlags_NoTitle)) {
			ImPlot::SetupAxes("T", "A", ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks, ImPlotAxisFlags_AutoFit | ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks);
			ImPlot::SetupAxesLimits(0, 1, -1, 1, ImPlotCond_Once);
			ImPlot::PlotStairs("", audio.debug_positions, audio.debug_wave_r, audio.debug_max_samples, audio.debug_pos);
			ImPlot::EndPlot();
		}
		ImPlot::DestroyContext();
		ImGui::End();
#endif

		video.UpdateTexture();

		// Pass inputs to sim
		top->inputs = 0;
		for (int i = 0; i < input_0.inputCount; i++)
		{
			if (input_0.inputs[i]) { top->inputs |= (1 << i); }
		}

		// Run simulation
		if (run_enable) {
			for (int step = 0; step < batchSize; step++) { verilate(); }
		}
		else {
			if (single_step) { verilate(); }
			if (multi_step) {
				for (int step = 0; step < multi_step_amount; step++) { verilate(); }
			}
		}
	}

	// Clean up before exit
	// --------------------

#ifndef DISABLE_AUDIO
	audio.CleanUp();
#endif
	video.CleanUp();
	input_0.CleanUp();

	return 0;
}
