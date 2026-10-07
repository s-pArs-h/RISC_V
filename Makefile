# RV32I cores: single-cycle (riscv_core) and 5-stage pipeline (riscv_pipeline)
#
#   make lint      Verilator -Wall on both cores (with and without RVFI) and the FPGA top
#   make isa       official riscv-tests RV32UI suite on both cores (40 tests each)
#   make random    cocotb random-instruction lockstep test on both cores
#   make formal    riscv-formal on both cores
#   make fpga-sim  Nexys A7 top level + demo program, both cores
#   make synth     Yosys resource estimates for Xilinx 7-series
#   make all       everything above
#
# Tools: iverilog, verilator, yosys, sby + yices, riscv64-unknown-elf-gcc,
#        python3 with cocotb >= 2.0. Submodules: git submodule update --init

COMMON  = rtl/riscv_decoder.sv rtl/riscv_imm_gen.sv rtl/riscv_alu.sv \
          rtl/riscv_regfile.sv rtl/riscv_lsu.sv
SINGLE  = $(COMMON) rtl/riscv_core.sv
PIPE    = $(COMMON) rtl/riscv_pipeline.sv
YOSYS_STAT = grep -E "^\s+(LUT[1-6]|RAM[0-9A-Z]+|FD[A-Z]+|CARRY4)\s" $(1) | \
  awk '{n[$$1 ~ /^LUT/ ? "LUT" : ($$1 ~ /^FD/ ? "FF" : $$1)] += $$2} END {for (k in n) printf "    %-8s %d\n", k, n[k]}' | sort

.PHONY: all lint isa random formal fpga-sim synth clean

all: lint isa random formal fpga-sim synth

lint:
	verilator --lint-only -Wall -Irtl $(SINGLE) --top-module riscv_core
	verilator --lint-only -Wall -Irtl -DRISCV_FORMAL $(SINGLE) --top-module riscv_core
	verilator --lint-only -Wall -Irtl $(PIPE) --top-module riscv_pipeline
	verilator --lint-only -Wall -Irtl -DRISCV_FORMAL $(PIPE) --top-module riscv_pipeline
	verilator --lint-only -Wall -Irtl -DSIM -GPIPELINED=0 fpga/top_nexys_a7.sv $(SINGLE) rtl/riscv_pipeline.sv --top-module top_nexys_a7
	verilator --lint-only -Wall -Irtl -DSIM -GPIPELINED=1 fpga/top_nexys_a7.sv $(SINGLE) rtl/riscv_pipeline.sv --top-module top_nexys_a7
	@echo "Verilator -Wall: clean"

isa:
	python3 tests/run_isa_tests.py --core single
	python3 tests/run_isa_tests.py --core pipeline

random:
	$(MAKE) -C tb CORE=riscv_core
	$(MAKE) -C tb CORE=riscv_pipeline

formal:
	formal/run.sh single
	formal/run.sh pipeline

fpga-sim: fpga/demo.hex
	@mkdir -p build
	@for p in 0 1; do \
	  iverilog -g2012 -DSIM -DPIPELINED=$$p -Irtl -o build/fpga_tb_$$p fpga/tb_top.sv fpga/top_nexys_a7.sv $(SINGLE) rtl/riscv_pipeline.sv || exit 1; \
	  vvp -n build/fpga_tb_$$p | grep -E "PASS|FAIL"; \
	  ! vvp -n build/fpga_tb_$$p | grep -q FAIL || exit 1; \
	done

fpga/demo.hex: sw/demo.S sw/link.ld
	$(MAKE) -C sw

synth:
	@mkdir -p build
	@yosys -q -p "read_verilog -sv -Irtl $(SINGLE); synth_xilinx -family xc7 -top riscv_core -flatten; tee -o build/synth_riscv_core.txt stat" > /dev/null
	@yosys -q -p "read_verilog -sv -Irtl $(PIPE); synth_xilinx -family xc7 -top riscv_pipeline -flatten; tee -o build/synth_riscv_pipeline.txt stat" > /dev/null
	@echo "  riscv_core (single-cycle):"; $(call YOSYS_STAT,build/synth_riscv_core.txt)
	@echo "  riscv_pipeline:";            $(call YOSYS_STAT,build/synth_riscv_pipeline.txt)

clean:
	rm -rf build tb/sim_build_* tb/results.xml tb/__pycache__ tb/coverage_*.txt sw/demo.elf sw/demo.bin
