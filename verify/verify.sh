#!/bin/bash

set -e

sby -d sby/qspi_ctrl -f qspi_ctrl.sby
sby -d sby/alu -f alu.sby
echo OK
