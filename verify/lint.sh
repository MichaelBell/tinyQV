#!/bin/bash

verilator --lint-only --timing -DSIM -DNO_SCRATCH -Wall -Wno-DECLFILENAME -Wno-MULTITOP -Wno-PROCASSINIT *.sv ../cpu/*.v ../peri/*/*.v
