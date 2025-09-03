# Tiny-QV: A Risc-V SoC for Tiny Tapeout <!-- omit in toc -->

A 4 bit at a time RV32 processor, optimized for use on Tiny Tapeout with QSPI RAM and Flash.

The aim of this design is to make a small microcontroller that is as fast as practical given the Tiny Tapeout constraints.

## Overview

RV32EC, Zcb, Zicond + a 32x16-bit multiplier

Basic interrupt support

QSPI flash/memory interface.  This uses a shared bus as I didn't think it was worth dedicating the pins to allow two completely separate interfaces (that would make load/store to RAM much faster, but adds complexity and we run out of outputs).

Peripherals including a UART and Tiny Tapeout competition entries.

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

Zcb and Zicond are implemented, along with a few custom instructions (to document).

EBREAK and ECALL are implemented, trapping with cause 3 and 11 respectively.

Hardcoding gp and tp doesn't significantly limit normal programs.  The C ABI reserves these registers, so it seems a sensible area saving.

TinyQV does not detect and correctly handle all traps/illegal/unsupported instructions, for area saving.  It is not aiming for full compliance with the Risc-V spec.

MRET is required to return from trap and interrupt handlers

CSRs:
- CYCLE - a 32 bit cycle counter, counts at clock/8 (once per possible instruction)
- TIME - returns CYCLE/8, so microseconds if clocked at 64MHz, wrapping at 2^32.
- INSTRET - is implemented
- MSTATUS - Only MIE and MPIE implemented, plus a non-standard trap enable bit at bit 2.
- MISA - read only
- MIMPID - indicates revision.  3 for this version.
- MTVEC - not implemented and non-standard behaviour.  On reset pc is set to 0x0, traps set pc to 0x4, interrupts to 0x8
- MIE & MIP - Custom interrupts only to give granularity, plus MTI.  Custom interrupts:
```
	16 - triggered on rising edge of in0 (cleared by clearing bit in MIP)
	17 - triggered on rising edge of in1 (cleared by clearing bit in MIP)
	18 - UART writeable  (cleared by writing byte to UART)
	19 - UART byte available  (cleared by reading byte from UART)
	20-31 - TT user contributed peripheral interrupts
```
- MEPC & MCAUSE - are implemented for trap and interrupt handling.  At boot execution starts at address 0 with cause 0.

Immediate forms of CSR instructions are not implemented.  MEPC can only be written with CSRRW.

### Custom instructions

TinyQV and the [TinyQV toolchain](https://github.com/MichaelBell/riscv-gnu-toolchain/releases/) support the following custom instructions:

| Instruction             | Operation |
| ----------------------- | --------- |
| `mul16 rd, rs1, rs2`    | Multiply rs1 by the bottom 16 bits of rs2. |
| `lw2 rd, offset(rs1)`   | Load 2 words into rd and r(d+1) from consecutive addresses.  This uses the same encoding as ld, provided by the Zilsd extension, but without the alignment requirements. |
| `lw4 rd, offset(rs1)`   | Load 4 words into rd to r(d+3) from consecutive addresses. |
| `sw2 rs2, offset(rs1)`  | Store 2 words from rs2 and r(s2+1) to consecutive addresses.  This uses the same encoding as sd, provided by the Zilsd extension, but without the alignment requirements. |
| `sw4 rs2, offset(rs1)`  | Store 4 words from rs2 to r(s2+3) to consecutive addresses. |
| `sw4n rs2, offset(rs1)` | Store rs2 4 times to consecutive addresses. |

When using the multiple word load and store instructions with peripherals the address wraps on a 16-byte boundary.  There is no such restriction when accessing flash or RAM.

Additionally there are compressed forms of lw and sw when using tp as the base register, to improve peripheral access performance.

The SDK provides 32 bit and 64 bit multiply implementations based on the 32x16 multiply.  However, if you know the top 16-bits of one of your arguments are 0 you can get significantly better performance using the `mul16` instruction directly.  The `mul32x16` function provided in `mul.h` facilitates this.

## Double fault / trap when inside a trap or interrupt handler

When entering a trap or interrupt handler further traps and interrupts are automatically disabled - mstatus.mie is set to 0 and the old value preserved in mstatus.mpie, and mstatus.mte is set to 0.

If a subsequent trap is hit while mstatus.mte is zero, this is an unrecoverable fault - if it entered the trap handler then the value of mepc would get overwritten, as would mstatus.mpie, so there would be no way to get back to the originally interrupted state.

Therefore, if a trap is hit while mstatus.mte is 0 then tinyQV sets pc to address 0 (same as reset), but MEPC and MCAUSE are set as normal so could be checked on reset to investigate the issue.  mstatus.mie and mte are set to 1 and mie and the clearable bits in mip are cleared, as for reset.

Having a separate trap enable bit means that it is not a double fault if a trap is hit in code that has disabled interrupts by clearing mstatus.mie.  mstatus.mte is read-only.

## QSPI memory interface

Use flash in continuous read mode.  Writes to flash not supported.  TinyQV expects the flash to be in continuous read mode when the core is started.  Bizarrely the datasheet doesn't seem to specify how to use continuous read mode - you have to look at W25Q80 instead, but this part is used with RP2040 and works (and it does mention continuous read in the overview), so I assume this is just a weird oversight.  The magic value for bits M7-M0 is 0xA0.  TinyQV expects the flash to be in continuous read mode when started.

In continuous read mode a QSPI read can be initiated with a 12 cycle preamble (6 cycles for the 24-bit address, 2 cycles for the mode, 4 dummy cycles).

Use the PSRAM in QPI mode.  TinyQV expects the PSRAM to be in QPI mode when the core is started.  
Writes have no delay cycles so 8 cycles + data (16 cycles total for a 32-bit write).
Use Fast Read (0Bh) for reads, (note 66MHz limit).  Gives 12 cycles preamble for read, 20 cycles total for a 32-bit read.

Code execution is only supported from the flash, this simplifies things a little and also removes the need for handling the PSRAM refresh every 8us in the case of long instruction sequences with no loads/stores/branches - all reads and writes to the PSRAM will be short.

## Address map

0x0000000 - 0x0FFFFFF: Flash (CS0)<br>
0x1000000 - 0x17FFFFF: RAM A (CS1)<br>
0x1800000 - 0x1FFFFFF: RAM B (CS2)<br>
0x8000000 = 0x80007FF: Peripheral registers (see TT repo)

## Pinout and peripherals

See [TT repo](https://github.com/TinyTapeout/ttsky25a-tinyQV/)

Peripherals are connected in the TT repo.  This version is setup to interface with a large number of peripherals.

## Instruction timing

Instruction timings below are in cycles of the internal 32-bit registers, which rotate 4 bits per clock, so each cycle is 8 clocks.

Note that instruction fetch is only capable of reading 16-bits per cycle, so 1 cycle/instruction throughput can only be maintained with compressed instructions.

| Instruction | Cycles |
| ----------- | ------ |
| AND/OR/XOR  | 1      |
| ADD/SUB     | 1      |
| LUI/AUIPC   | 1      |
| SLT         | 2      |
| Shifts      | 2      |
| Mul (32x16) | 2      |
| CZERO (condition true) | 1 |
| CZERO (condition false) | 2 |
| JAL         | 5      |
| RET         | 5      |
| Other JALR  | 6      |
| Branch (not taken) | 1 |
| Branch (taken) | 7   |
| Store to peripheral   | 1 | 
| 8 or 16-bit store to PSRAM   | 5-6    |
| Store word to PSRAM        | 6-7    |
| Store 2 words to PSRAM        | 10-11    |
| Store 4 words to PSRAM        | 14-15    |
| Load from peripheral  | 3 |
| 8 or 16-bit load from flash/PSRAM | 8-9    |
| Load word from flash/PSRAM | 9-10    |
| Load 2 words from flash/PSRAM | 15-16    |
| Load 4 words from flash/PSRAM | 23-24    |

## FPGA testing

See the [TT repo](https://github.com/TinyTapeout/ttsky25a-tinyQV/) for details on [testing on pico-ice](https://github.com/TinyTapeout/ttsky25a-tinyQV/tree/main/fpga/pico-ice) or [on other FPGAs](https://github.com/TinyTapeout/ttsky25a-tinyQV/tree/main/fpga/generic).
