import time
import sys
import rp2
import machine
from machine import UART, Pin, PWM, SPI

import flash_prog

@rp2.asm_pio(autopush=True, push_thresh=8, in_shiftdir=rp2.PIO.SHIFT_LEFT,
             autopull=True, pull_thresh=8, out_shiftdir=rp2.PIO.SHIFT_RIGHT,
             out_init=(rp2.PIO.IN_HIGH, rp2.PIO.OUT_HIGH, rp2.PIO.OUT_HIGH, rp2.PIO.IN_HIGH,
                       rp2.PIO.IN_HIGH, rp2.PIO.IN_HIGH, rp2.PIO.OUT_HIGH, rp2.PIO.OUT_HIGH),
             sideset_init=(rp2.PIO.OUT_HIGH))
def qspi_read():
    out(x, 8).side(1)
    out(y, 8).side(1)
    out(pindirs, 8).side(1)
    
    label("cmd_loop")
    out(pins, 8).side(0)
    jmp(x_dec, "cmd_loop").side(1)
    
    out(pindirs, 8).side(0)
    label("data_loop")
    in_(pins, 8).side(1)
    jmp(y_dec, "data_loop").side(0)
    
    out(pins, 8).side(1)
    out(pindirs, 8).side(1)

@rp2.asm_pio(autopush=True, push_thresh=32, in_shiftdir=rp2.PIO.SHIFT_RIGHT)
def pio_capture():
    in_(pins, 8)
    
def spi_cmd(spi, data, sel, dummy_len=0, read_len=0):
    dummy_buf = bytearray(dummy_len)
    read_buf = bytearray(read_len)
    
    sel.off()
    spi.write(bytearray(data))
    if dummy_len > 0:
        spi.readinto(dummy_buf)
    if read_len > 0:
        spi.readinto(read_buf)
    sel.on()
    
    return read_buf

def setup_flash():
    spi = SPI(0, 32_000_000, sck=Pin(2), mosi=Pin(3), miso=Pin(0))

    flash_sel = Pin(1, Pin.OUT)
    ram_a_sel = Pin(4, Pin.OUT)
    ram_b_sel = Pin(6, Pin.OUT)
    
    # Leave CM mode if in it
    spi_cmd(spi, [0xFF], flash_sel)

    sm = rp2.StateMachine(0, qspi_read, 16_000_000, in_base=Pin(0), out_base=Pin(0), sideset_base=Pin(2))
    sm.active(1)
    
    # Read 1 byte from address 0 to get into continuous read mode
    num_bytes = 1
    buf = bytearray(num_bytes*2 + 4)
    
    sm.put(8+6+2-1)     # Command + Address + Dummy - 1
    sm.put(num_bytes*2 + 4 - 1) # Data + Dummy - 1
    sm.put(0b11111111)  # Directions
    
    sm.put(0b01011000)  # Command
    sm.put(0b01011000)
    sm.put(0b01011000)
    sm.put(0b01010000)
    sm.put(0b01011000)
    sm.put(0b01010000)
    sm.put(0b01011000)
    sm.put(0b01011000)
    
    sm.put(0b01010000)  # Address
    sm.put(0b01010000)
    sm.put(0b01010000)
    sm.put(0b01010000)
    sm.put(0b01010000)
    sm.put(0b01010000)
    sm.put(0b11010001) # SD3, RAM_B_SEL, SD2, RAM_A_SEL, SD0, SCK, CS, SD1
    sm.put(0b11010001)
    
    sm.put(0b01010110)  # Directions
    
    for i in range(num_bytes*2 + 4):
        buf[i] = sm.get()
        
    sm.put(0b11111111)
    sm.put(0b01010110)  # Directions
    sm.active(0)
    del sm

def setup_ram():
    spi = SPI(0, 32_000_000, sck=Pin(2), mosi=Pin(3), miso=Pin(0))

    flash_sel = Pin(1, Pin.OUT)
    ram_a_sel = Pin(4, Pin.OUT)
    ram_b_sel = Pin(6, Pin.OUT)

    flash_sel.on()
    ram_a_sel.on()
    ram_b_sel.on()
    
    for sel in (ram_a_sel, ram_b_sel):
        spi_cmd(spi, [0x35], sel)

def run(query=True, stop=True):
    machine.freq(112_000_000)

    for i in range(30):
        Pin(i, Pin.IN, pull=None)

    flash_sel = Pin(17, Pin.IN, Pin.PULL_UP)
    ice_creset_b = machine.Pin(27, machine.Pin.OUT)
    ice_creset_b.value(0)
    
    setup_flash()
    setup_ram()

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

    sm = rp2.StateMachine(1, pio_capture, 28_000_000, in_base=Pin(0))

    capture_len=1024
    buf = bytearray(capture_len)

    rx_dma = rp2.DMA()
    c = rx_dma.pack_ctrl(inc_read=False, treq_sel=5) # Read using the SM0 RX DREQ
    sm.restart()
    sm.exec("wait(%d, gpio, %d)" % (0, 4))
    rx_dma.config(
        read=0x5020_0024,        # Read from the SM1 RX FIFO
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
    clk = PWM(Pin(24), freq=14_000_000, duty_u16=32768)

    # Wait for DMA to complete
    while rx_dma.active():
        time.sleep_ms(1)
        
    sm.active(0)
    del sm

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
