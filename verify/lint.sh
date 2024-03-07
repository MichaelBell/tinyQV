#!/bin/bash

verilator --lint-only -DSIM --timing -Wall -Wno-DECLFILENAME -Wno-MULTITOP *.sv ../cpu/*.v
