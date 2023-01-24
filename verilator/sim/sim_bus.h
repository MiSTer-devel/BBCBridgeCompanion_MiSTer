#pragma once
#include <queue>
#include "verilated_heavy.h"
#include "sim_console.h"


#ifndef _MSC_VER
#else
#define WIN32
#endif

struct SimBus_DownloadChunk {
public:
	std::string file;
	std::queue<char> contentQueue;
	std::string label;
	bool isQueue;
	int index;
	bool restart;
	
	SimBus_DownloadChunk() {
		file = "";
		index = -1;
	}

	SimBus_DownloadChunk(std::string file, int index) {
		this->restart = false;
		this->file = std::string(file);
		this->label = std::string(file);
		this->index = index;
		this->isQueue = false;
	}
	SimBus_DownloadChunk(std::string file, int index, bool restart) {
		this->restart = restart;
		this->file = std::string(file);
		this->label = std::string(file);
		this->index = index;
		this->isQueue = false;
	}
	SimBus_DownloadChunk(int index, bool restart, std::string label) {
		this->restart = restart;
		this->contentQueue = std::queue<char>();
		this->index = index;
		this->isQueue = true;
		this->label = std::string(label);
	}
};

struct SimBus {
public:

	IData* ioctl_addr;
	CData* ioctl_index;
	CData* ioctl_wait;
	CData* ioctl_download;
	CData* ioctl_upload;
	CData* ioctl_wr;
	CData* ioctl_dout;
	CData* ioctl_din;

	void BeforeEval(void);
	void AfterEval(void);
	void QueueDownload(std::string file, int index);
	void QueueDownload(std::string file, int index, bool restart);
	bool HasQueue();
	void LoadMRA(std::string file);

	SimBus(DebugConsole c);
	~SimBus();

private:
	std::queue<SimBus_DownloadChunk> downloadQueue;
	SimBus_DownloadChunk currentDownload;
	void SetDownload(std::string file, int index);
};
