#!/bin/bash

verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-MULTITOP *.v
