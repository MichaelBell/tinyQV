#!/bin/bash

verilator --lint-only --timing -DSIM -Wall -Wno-DECLFILENAME -Wno-MULTITOP *.sv ../cpu/*.v ../peri/*/*.v
