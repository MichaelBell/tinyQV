#!/bin/bash

verilator --lint-only --timing -DSIM -Wall -Wno-DECLFILENAME -Wno-MULTITOP -Wno-PROCASSINIT *.sv ../cpu/*.v ../peri/*/*.v
