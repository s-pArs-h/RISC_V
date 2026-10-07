# RV32I core: top-level flows
#
#   make lint      Verilator -Wall on the core (with and without RVFI) and FPGA top
#   make isa       official riscv-tests RV32UI suite (40 tests)
#   make random    cocotb random-instruction lockstep test against the Python ISS
#   make formal    riscv-formal: every instruction checked against the ISA spec
#   make fpga-sim  run the Nexys A7 top level + demo program in simulation
#   make synth     Yosys resource estimate for Xilinx 7-series
#   make all       everything above
#
# Tools: iverilog, verilator, yosys, sby + yices, riscv64-unknown-elf-gcc,
#        python3 with cocotb >= 2.0. Submodules: git submodule update --init

CORE_RTL = rtl/riscv_decoder.sv rtl/riscv_imm_gen.sv rtl/riscv_alu.sv \
           rtl/riscv_regfile.sv rtl/riscv_lsu.sv rtl/riscv_core.sv

.PHONY: all lint isa random formal fpga-sim synth clean

all: lint isa random formal fpga-sim synth

lint:
	verilator --lint-only -Wall -Irtl $(CORE_RTL) --top-module riscv_core
	verilator --lint-only -Wall -Irtl -DRISCV_FORMAL $(CORE_RTL) --top-module riscv_core
	verilator --lint-only -Wall -Irtl -DSIM fpga/top_nexys_a7.sv $(CORE_RTL) --top-module top_nexys_a7
	@echo "Verilator -Wall: clean"

isa:
	python3 tests/run_isa_tests.py

random:
	$(MAKE) -C tb

formal:
	formal/run.sh single

fpga-sim: fpga/demo.hex
	@mkdir -p build
	iverilog -g2012 -DSIM -Irtl -o build/fpga_tb fpga/tb_top.sv fpga/top_nexys_a7.sv $(CORE_RTL)
	vvp -n build/fpga_tb | grep -E "PASS|FAIL"
	@! vvp -n build/fpga_tb | grep -q FAIL

fpga/demo.hex: sw/demo.S sw/link.ld
	$(MAKE) -C sw

synth:
	@mkdir -p build
	yosys -q -p "read_verilog -sv -Irtl $(CORE_RTL); synth_xilinx -family xc7 -top riscv_core -flatten; tee -o build/synth_riscv_core.txt stat" > /dev/null
	@grep -E "^\s+(LUT[1-6]|RAM[0-9A-Z]+|FD[A-Z]+|CARRY4|MUXF[78])\s" build/synth_riscv_core.txt | \
	  awk '{n[$$1 ~ /^LUT/ ? "LUT" : ($$1 ~ /^FD/ ? "FF" : $$1)] += $$2} END {for (k in n) printf "  %-10s %d\n", k, n[k]}' | sort

clean:
	rm -rf build tb/sim_build_* tb/results.xml tb/__pycache__ tb/coverage_*.txt sw/demo.elf sw/demo.bin
	rm -rf formal/riscv-formal/cores/rv32i_*
