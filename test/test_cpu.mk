# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

CPUD = $(PWD)/../cpu
VERILOG_SOURCES += $(CPUD)/cpu.v $(CPUD)/decode.v $(CPUD)/core.v $(CPUD)/alu.v $(CPUD)/register.v $(CPUD)/counter.v $(CPUD)/time.v  $(PWD)/tb_cpu.v
COMPILE_ARGS    += -DSIM

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = tb_cpu

# MODULE is the basename of the Python test file
MODULE = test_cpu

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim