#pragma once
#include "imgui.h"

struct DebugConsole {
public:

	long main_time;

	void AddLog(const char* fmt, ...) IM_FMTARGS(2);
	DebugConsole();
	~DebugConsole();
	void ClearLog(); 
	void LimitTo(unsigned int max);
	void Draw(const char* title, bool* p_open, ImVec2 size);
	void    ExecCommand(const char* command_line);
	int     TextEditCallback(ImGuiInputTextCallbackData* data);
};
