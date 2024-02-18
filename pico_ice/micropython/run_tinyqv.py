import time
import sys
import rp2
import machine
from machine import UART, Pin, PWM

import flash_prog

def run(query=True, stop=True):
    machine.freq(128_000_000)

    for i in range(30):
        Pin(i, Pin.IN, pull=None)

    flash_sel = Pin(17, Pin.IN, Pin.PULL_UP)
    ice_creset_b = machine.Pin(27, machine.Pin.OUT)
    ice_creset_b.value(0)

    ice_done = machine.Pin(26, machine.Pin.IN)
    time.sleep_us(10)
    ice_creset_b.value(1)

    while ice_done.value() == 0:
        print(".", end = "")
        time.sleep(0.001)
    print()

    if query:
        input("Reset? ")

    rst_n = Pin(12, Pin.OUT)
    clk = Pin(24, Pin.OUT)

    clk.off()
    rst_n.on()
    time.sleep(0.001)
    rst_n.off()

    clk.on()
    time.sleep(0.001)
    clk.off()
    time.sleep(0.001)

    flash_sel = Pin(1, Pin.OUT)
    qspi_sd0  = Pin(3, Pin.OUT)
    qspi_sd1  = Pin(0, Pin.OUT)
    qspi_sd2  = Pin(5, Pin.OUT)
    ram_a_sel = Pin(4, Pin.OUT)
    ram_b_sel = Pin(6, Pin.OUT)

    flash_sel.on()
    ram_a_sel.on()
    ram_b_sel.on()
    qspi_sd0.on()
    qspi_sd1.off()
    qspi_sd2.off()

    for i in range(10):
        clk.off()
        time.sleep(0.001)
        clk.on()
        time.sleep(0.001)

    Pin(1, Pin.IN, pull=Pin.PULL_UP)
    Pin(2, Pin.IN, pull=Pin.PULL_DOWN)
    Pin(3, Pin.IN, pull=None)
    Pin(0, Pin.IN, pull=None)
    Pin(4, Pin.IN, pull=Pin.PULL_UP)
    Pin(5, Pin.IN, pull=None)
    Pin(6, Pin.IN, pull=Pin.PULL_UP)
    Pin(7, Pin.IN, pull=None)

    rst_n.on()
    time.sleep(0.001)
    clk.off()

    @rp2.asm_pio(autopush=True, push_thresh=32, in_shiftdir=rp2.PIO.SHIFT_RIGHT)
    def pio_capture():
        in_(pins, 8)
        
    sm = rp2.StateMachine(0, pio_capture, 32_000_000, in_base=Pin(0))

    capture_len=4096
    buf = bytearray(capture_len)

    rx_dma = rp2.DMA()
    c = rx_dma.pack_ctrl(inc_read=False, treq_sel=4) # Read using the SM0 RX DREQ
    sm.restart()
    sm.exec("wait(%d, gpio, %d)" % (0, 1))
    rx_dma.config(
        read=0x5020_0020,        # Read from the SM0 RX FIFO
        write=buf,
        ctrl=c,
        count=capture_len//4,
        trigger=True
    )
    sm.active(1)

    if query:
        input("Start? ")

    #uart = UART(0, baudrate=115200, tx=Pin(0), rx=Pin(1))
    time.sleep(0.001)
    clk = PWM(Pin(24), freq=16_000_000, duty_u16=32768)

    # Wait for DMA to complete
    while rx_dma.active():
        time.sleep_ms(1)

    if not stop:
        return

    if query:
        input("Stop? ")

    del clk
    Pin(12, Pin.IN, pull=Pin.PULL_DOWN)
    Pin(24, Pin.IN, pull=Pin.PULL_DOWN)

    if False:
        while True:
            data = uart.read(16)
            if data is not None:
                for d in data:
                    if d > 0 and d <= 127:
                        print(chr(d), end="")

        for i in range(len(buf)):
            print("%02x " % (buf[i],), end = "")
            if (i & 7) == 7:
                print()

    if False:
        for j in (1, 2, 3, 0, 5, 7, 4, 6):
            print("%02d: " % (j,), end="")
            for d in buf:
                print("-" if (d & (1 << j)) != 0 else "_", end = "")
            print()

        print("SD: ", end="")
        for d in buf:
            nibble = ((d >> 3) & 1) | ((d << 1) & 2) | ((d >> 3) & 0x4) | ((d >> 4) & 0x8)
            print("%01x" % (nibble,), end="")
        print()

def execute(filename):
    flash_prog.program(filename)
    run(query=False, stop=False)
