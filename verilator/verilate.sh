export OPTIMIZE="-O3 --x-assign fast --x-initial fast --noassert"
export WARNINGS="-Wno-fatal -Wno-LITENDIAN"

set -e
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null ; then
verilator \
-cc --compiler msvc +define+SIMULATION=1 $WARNINGS $OPTIMIZE \
--converge-limit 6000 \
--top-module emu sim.v \
-I../rtl \
-I../rtl/tv80 \
-I../rtl/z8420 \
../rtl/vdp18/vdp18_pkg.sv \
-I../rtl/vdp18
else
	echo "not running on windows"
fi
