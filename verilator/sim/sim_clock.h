#pragma once

class SimClock
{

public:
	bool clk, old;

	SimClock();
	SimClock(int r);
	~SimClock();
	void Tick();
	void Reset();
	bool IsRising();
	bool IsFalling();

private:
	int ratio, count;
};