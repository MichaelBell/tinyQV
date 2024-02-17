# Tiny-QV: A Risc-V SoC for Tiny Tapeout <!-- omit in toc -->

Idea is to implement a 4 bit at a time RV32 processor, similar to [nanoV](https://github.com/MichaelBell/nanoV) but optimized for QSPI RAM and Flash instead of SPI FRAM.

Aim will be to fit in a 2x2 tile size.  Guiding principle is fast as practical on Tiny Tapeout while minimizing area.

## Design goals

RV32EC (maybe some partial support for M?)

Basic interrupt support

QSPI flash/memory interface, don't think it is worth dedicating the pins to allow two completely separate interfaces (potentially makes load/store to RAM much faster, but adds complexity and we run out of outputs).

Peripherals so it can do basic microcontroller things, currently thinking 1 UART and 1 SPI master, plus some GPIOs.

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

Core should be timed to run at up to 100MHz, QSPI at 50MHz

Should be able to execute 1 cycle 16-bit instructions at one instruction every 8 cycles (up to ~12MHz), shifts and 32-bit instructions (other than branches and stores) every 16 cycles (up to ~6MHz)

## Risc-V details

Fullish RV32EC, with a few exceptions:
- Addresses are 28-bits
- gp is hardcoded to 0x1000400, tp is hardcoded to 0x8000000.  Peripherals will have addresses in the 2K above tp, so it can be used for fast access.  gp can be used for fast access to data at the bottom of flash.

Only M mode is supported.

Unlike nanoV, EBREAK and ECALL will be implemented, trapping with cause 3 and 11 respectively.

Hardcoding gp and tp - it doesn't seem to have caused any trouble in running general code on nanoV, and is similar to the "normal" ABI usage of these registers, so it seems a sensible saving.

Will not bother trying to detect and correctly handle all traps/illegal/unsupported instructions, for area saving.  Not aiming for full compliance.

Would be nice to implement WFI

No need for MRET - only M mode is supported so the trap handler can simply jump to mepc+4

CSRs:
- CYCLE - will provide a 32 (or possibly 24) bit cycle counter
- TIME - will return CYCLE - or could we have a programmable divider?
- INSTRET - would be nice to provide this
- (MSTATUS - probably not bother)
- MISA - read only
- (MTVEC - probably not bother, or read only, hardcode to 0.)
- MIE & MIP - yes, but custom interrupts only - MSI/MTI/MEI probably not implemented as the spec'd behaviour is a bit odd.  Custom interrupts:
```
    16 - triggered on rising edge of in0 (cleared by clearing bit in MIP)
	17 - triggered on rising edge of in1 (cleared by clearing bit in MIP)
	18 - UART byte available  (cleared by reading byte from UART)
	19 - Maybe a timer if we get that far?
```

- MEPC & MCAUSE - required for interrupt handling.  At boot execution starts at address 0 with cause 0.

## QSPI memory interface

Use flash in continuous read mode.  Writes to flash not supported.  On boot will enter continuous read mode once when reading the instruction at address 0.  Bizarrely the datasheet doesn't seem to specify how to use continuous read mode - you have to look at W25Q80 instead, but this part is used with RP2040 and works (and it does mention continuous read in the overview), so I assume this is just a weird oversight.  The magic value for bits M7-M0 is 0xA0.

In continuous read mode a QSPI read can be initiated with a 12 cycle preamble (6 cycles for the 24-bit address, 2 cycles for the mode, 4 dummy cycles).

Use the PSRAM in QPI mode.  Enter quad mode on each RAM immediately after reset (this should be safely ignored if they are already in quad mode).
Writes have no delay cycles so 8 cycles + data (16 cycles total for a 32-bit write).
Use Fast Read (0Bh) for reads, (note 66MHz limit).  Gives 12 cycles preamble for read, 20 cycles total for a 32-bit read.

My thought is that code execution is only supported from the flash, this potentially simplifies things a little and also removes the need for handling the PSRAM refresh every 8us in the case of long instruction sequences with no loads/stores/branches - all reads and writes to the PSRAM will be short.

Overall this means that stores to RAM are likely to cost at least 20 SPI clocks = 5 minimum cost instructions, and loads 24 = 6 minimum cost instructions.  So similar proportional cost as nanoV, but the baseline is 8x faster.

## Address map

0x0000000 - 0x0FFFFFF: Flash (CS0)
0x1000000 - 0x17FFFFF: RAM A (CS1)
0x1800000 - 0x1FFFFFF: RAM B (CS2)
0x8000000 = 0x80007FF: Peripheral registers (TBD)

## Pinout

```
bidis - QSPI PMOD as above

in0 - Interrupt 0
in1 - Interrupt 1
in2 - SPI MISO
in3 - UART RX
in4 - GPIO
in5 - GPIO
in6 - GPIO
in7 - GPIO

out0 - SPI CS
out1 - SPI SCK
out2 - SPI MOSI
out3 - GPIO (DC)
out4 - UART TX
out5 - UART RTS
out6 - GPIO
out7 - GPIO
```

## Peripherals

Probably stick to the same UART as in nanoV, maybe configured for 115200 when running at 66MHz?  Not loads of point in extra buffering as could only afford another byte or two and you normally printf a bunch of chars together.

SPI is new.  Find/write a simple controller.  Target is to make using the ST7789 screen reasonably painless - maybe could support D/C toggling?  Maybe 1 extra byte of buffer (make it configurable), mostly as a proof of concept.

## FPGA testing

Plan is to do initial testing with the Pico-Ice.  Advantages of this:
- The FPGA has access to 4MB QSPI flash and 8MB QSPI PSRAM
- You can use the whole of the flash, because the FPGA bitstream can be loaded from the separate RP2040 flash
- RP2040 can work as a logic analyser for debugging, and is good for testing UART, SPI and GPIO peripherals too.