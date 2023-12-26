# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

CPUD = $(PWD)/../cpu
VERILOG_SOURCES += $(CPUD)/qspi_flash.v $(PWD)/tb_qspi_flash.v
COMPILE_ARGS    += -DSIM

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = tb_qspi_flash

# MODULE is the basename of the Python test file
MODULE = test_qspi_flash

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim