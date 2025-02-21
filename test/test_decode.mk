# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

CPUD = $(PWD)/../cpu
VERILOG_SOURCES += $(CPUD)/decode.v $(PWD)/tb_decode.v
COMPILE_ARGS    += -DSIM -Ptb_decode.XLEN=$(XLEN)

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = tb_decode

# MODULE is the basename of the Python test file
MODULE = test_decode

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
