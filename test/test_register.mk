# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

CPUD = $(PWD)/../cpu
VERILOG_SOURCES += $(CPUD)/register.v $(PWD)/tb_register.v
COMPILE_ARGS    += -DSIM

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = tb_register

# MODULE is the basename of the Python test file
MODULE = test_register

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim