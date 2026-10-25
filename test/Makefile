SIM ?= icarus
FST ?= -fst
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src

# Which phase to build and test:  make PHASE=0 | 1 | 2 | 3   (3 = everything, also used after Phase 3)
PHASE ?= 0
ifeq ($(PHASE),0)
PROJECT_SOURCES = project_phase0.v uart_tx.v baud_gen.v
COCOTB_TEST_MODULES = test_phase0
else ifeq ($(PHASE),1)
PROG ?= uart_tx_v0.s
$(shell python3 ../tools/asm.py ../programs/$(PROG) -o /dev/null --vh ../src/rom.vh > /dev/null)
PROJECT_SOURCES = project_phase1.v pe_core.v
COCOTB_TEST_MODULES = test_phase1
export PROG
else
# Phase 2 runs the tests that need no I2C model; PHASE=3 (and later) runs everything
PROJECT_SOURCES = project.v pe_core.v pe_host.v pe_fifo.v
COCOTB_TEST_MODULES = test
ifeq ($(PHASE),2)
COCOTB_TEST_FILTER ?= 'test_registers|test_uart|test_spi|test_sniffer'
export COCOTB_TEST_FILTER
endif
endif

ifneq ($(GATES),yes)
SIM_BUILD = sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
else
SIM_BUILD = sim_build/gl
COMPILE_ARGS += -DGL_TEST -DFUNCTIONAL -DSIM
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_io/verilog/sg13cmos5l_io.v
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_udp.v
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v
endif

COMPILE_ARGS += -I$(SRC_DIR)
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb
include $(shell cocotb-config --makefiles)/Makefile.sim
