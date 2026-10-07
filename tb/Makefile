# cocotb random-instruction test (Icarus Verilog)
#   make               single-cycle core, SEED=1, N=40 programs per test
#   make SEED=7 N=200  another seed, more programs
#   make WAVES=1       dump waveforms

SIM          ?= icarus
TOPLEVEL_LANG = verilog
SEED         ?= 1
N            ?= 40
CORE         ?= riscv_core

RTL = $(abspath ../rtl)
ifeq ($(CORE),riscv_core)
  CORE_SOURCES = $(RTL)/riscv_decoder.sv $(RTL)/riscv_imm_gen.sv $(RTL)/riscv_alu.sv \
                 $(RTL)/riscv_regfile.sv $(RTL)/riscv_lsu.sv $(RTL)/riscv_core.sv
endif

VERILOG_SOURCES     = $(abspath sim_mem.sv) $(abspath tb_rvfi.sv) $(CORE_SOURCES)
COCOTB_TOPLEVEL     = tb_rvfi
COCOTB_TEST_MODULES = test_random
SIM_BUILD           = sim_build_$(CORE)
COMPILE_ARGS       += -I$(RTL) -DRISCV_FORMAL -DCORE=$(CORE)

export SEED N
export COVERAGE_REPORT = coverage_$(CORE).txt

include $(shell cocotb-config --makefiles)/Makefile.sim
