# Tiny-QV: A Risc-V SoC for Tiny Tapeout <!-- omit in toc -->

A 4 bit at a time RV32 processor, similar to [nanoV](https://github.com/MichaelBell/nanoV) but optimized for QSPI RAM and Flash instead of SPI FRAM.

The aim of this design is to make a small microcontroller that is as fast as practical given the Tiny Tapeout constraints, and sticking to a 2x2 tile size.

## Overview

RV32EC + a 32x16-bit multiplier

Basic interrupt support  (not yet implemented)

QSPI flash/memory interface.  This uses a shared bus as I didn't think it was worth dedicating the pins to allow two completely separate interfaces (that would make load/store to RAM much faster, but adds complexity and we run out of outputs).

Peripherals so it can do basic microcontroller things, currently 1 UART and 1 SPI master, plus some GPIOs.

### QPSI PMOD

Using [this PMOD](https://github.com/mole99/qspi-pmod) for the bidis with W25Q128JVSIQ (16MB flash) and 2xAPS6404L-3SQR-SN (8MB RAM).

The pinout for the PMOD is
```
	uio[0] - CS0 (Flash)
	uio[1] - SD0/MOSI
	uio[2] - SD1/MISO
	uio[3] - SCK
	uio[4] - SD2
	uio[5] - SD3
	uio[6] - CS1 (RAMA)
	uio[7] - CS2 (RAMB)
```

### Performance

STA should pass at 100MHz on sky130.  But it is likely not to actually work that fast due to the slow TT outputs.  The intended clock speed for the design is 64MHz, which runs the QSPI at 32MHz.

Should be able to execute 1 cycle 16-bit instructions at one instruction every 8 cycles (at ~8MHz), shifts and 32-bit instructions (other than branches and stores) every 16 cycles (~4MHz).

## Risc-V details

Fullish RV32EC, with a few exceptions:
- Addresses are 28-bits
- gp is hardcoded to 0x1000400, tp is hardcoded to 0x8000000.  Peripherals will have addresses in the 2K above tp, so it can be used for fast access.  gp can be used for fast access to data at the bottom of RAM.

Only M mode is supported.

Zcb is implemented, along with a few custom instructions (to document).

Unlike nanoV, EBREAK and ECALL will be implemented, trapping with cause 3 and 11 respectively.

Hardcoding gp and tp - it doesn't seem to have caused any trouble in running general code on nanoV, and is similar to the "normal" ABI usage of these registers, so it seems a sensible saving.

Will not bother trying to detect and correctly handle all traps/illegal/unsupported instructions, for area saving.  Not aiming for full compliance.

MRET is required to return from trap and interrupt handlers

CSRs:
- CYCLE - a 32 bit cycle counter, counts at clock/8 (once per possible instruction)
- TIME - returns CYCLE/8, so microseconds if clocked at 64MHz, wrapping at 2^32.
- INSTRET - is implemented
- MSTATUS - Only MIE and MPIE implemented, plus a non-standard trap enable bit at bit 2.
- MISA - read only
- MTVEC - not implemented and non-standard behaviour.  On reset pc is set to 0x0, traps set pc to 0x4, interrupts to 0x8
- MIE & MIP - Custom interrupts only to give granularity, might implement MTI if there's room for a timer.  Custom interrupts:
```
    16 - triggered on rising edge of in0 (cleared by clearing bit in MIP)
	17 - triggered on rising edge of in1 (cleared by clearing bit in MIP)
	18 - UART byte available  (cleared by reading byte from UART)
	19 - UART writeable  (cleared by writing byte to UART)
```

- MEPC & MCAUSE - required for trap and interrupt handling.  At boot execution starts at address 0 with cause 0.

Immediate forms of CSR instructions are not implemented.  MEPC can only be written with CSRRW.

## Double fault / trap when inside a trap or interrupt handler

When entering a trap or interrupt handler further traps and interrupts are automatically disabled - mstatus.mie is set to 0 and the old value preserved in mstatus.mpie, and mstatus.mte is set to 0.

If a subsequent trap is hit while mstatus.mte is zero, this is an unrecoverable fault - if it entered the trap handler then the value of mepc would get overwritten, as would mstatus.mpie, so there would be no way to get back to the originally interrupted state.

Therefore, if a trap is hit while mstatus.mte is 0 then tinyQV sets pc to address 0 (same as reset), but MEPC and MCAUSE are set as normal so could be checked on reset to investigate the issue.  mstatus.mie and mte are set to 1 and mie and the clearable bits in mip are cleared, as for reset.

Having a separate trap enable bit means that it is not a double fault if a trap is hit in code that has disabled interrupts by clearing mstatus.mie.  mstatus.mte is read-only.

## QSPI memory interface

Use flash in continuous read mode.  Writes to flash not supported.  TinyQV expects the flash to be in continuous read mode when the core is started.  Bizarrely the datasheet doesn't seem to specify how to use continuous read mode - you have to look at W25Q80 instead, but this part is used with RP2040 and works (and it does mention continuous read in the overview), so I assume this is just a weird oversight.  The magic value for bits M7-M0 is 0xA0.

In continuous read mode a QSPI read can be initiated with a 12 cycle preamble (6 cycles for the 24-bit address, 2 cycles for the mode, 4 dummy cycles).

Use the PSRAM in QPI mode.  TinyQV expects the PSRAM to be in QPI mode when the core is started.  
Writes have no delay cycles so 8 cycles + data (16 cycles total for a 32-bit write).
Use Fast Read (0Bh) for reads, (note 66MHz limit).  Gives 12 cycles preamble for read, 20 cycles total for a 32-bit read.

My thought is that code execution is only supported from the flash, this potentially simplifies things a little and also removes the need for handling the PSRAM refresh every 8us in the case of long instruction sequences with no loads/stores/branches - all reads and writes to the PSRAM will be short.

Overall this means that stores to RAM are likely to cost at least 20 SPI clocks = 5 minimum cost instructions, and loads 24 = 6 minimum cost instructions.  So similar proportional cost as nanoV, but the baseline is 8x faster.

## Address map

0x0000000 - 0x0FFFFFF: Flash (CS0)
0x1000000 - 0x17FFFFF: RAM A (CS1)
0x1800000 - 0x1FFFFFF: RAM B (CS2)
0x8000000 = 0x80007FF: Peripheral registers (see TT06 repo)

## Pinout

See [TT06 repo](https://github.com/MichaelBell/tt06-tinyQV/)

## Peripherals

The same UART as in nanoV, configured for 115200 when running at 64MHz.

An additional TX only UART for debugging, the SDK outputs stderr to this, its configured for 4Mbit at 64MHz clock.

A simple SPI controller is implemented.  Target is to make using the ST7789 screen reasonably painless, so it supports toggling a D/C line.

## Instruction timing

Instruction timings below are in cycles of the internal 32-bit registers, which rotate 4 bits per clock, so each cycle is 8 clocks.

Note that instruction fetch is only capable of reading 16-bits per cycle, so 1 cycle/instruction throughput can only be maintained with compressed instructions.

| Instruction | Cycles |
| ----------- | ------ |
| AND/OR/XOR  | 1      |
| ADD/SUB     | 1      |
| LUI/AUIPC   | 1      |
| SLT         | 1      |
| Shifts      | 2      |
| Mul (32x16) | 2      |
| JAL         | 5      |
| RET         | 5      |
| Other JALR  | 6      |
| Branch (not taken) | 1 |
| Branch (taken) | 7   |
| Store to peripheral   | 1 | 
| Store to PSRAM        | ~5    |
| Load from peripheral  | 3 |
| Load from flash/PSRAM | ~7    |

## FPGA testing

Initial testing has been done with a Pico-Ice.  This allows things to be set up in a similar way to the TT demo board, with MicroPython loading the program into the flash on the QSPI PMOD, and then starting the FPGA.  See the pico-ice directory for implementation.
