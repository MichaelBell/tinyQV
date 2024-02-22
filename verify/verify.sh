#!/bin/bash

set -e

./lint.sh
sby -d sby/qspi_ctrl -f qspi_ctrl.sby
sby -d sby/alu_simple -f alu.sby alu
sby -d sby/alu_shift -f alu.sby shift

# Leaving multiply commented out as this takes several minutes
#sby -d sby/alu_mul -f alu.sby mul 

echo OK
