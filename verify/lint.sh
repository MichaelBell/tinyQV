#!/bin/bash

verilator --lint-only -DSIM -Wall -Wno-DECLFILENAME -Wno-MULTITOP *.sv ../cpu/*.v
