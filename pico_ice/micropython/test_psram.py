import time
import random
from machine import SPI, Pin
machine.freq(128_000_000)
spi = SPI(1, 16_000_000)

flash_sel = Pin(9, Pin.OUT)
ram_a_sel = Pin(14, Pin.OUT)
ram_b_sel = Pin(15, Pin.OUT)

flash_sel.on()
ram_a_sel.on()
ram_b_sel.on()

CMD_WRITE = 0x02
CMD_READ = 0x03

def spi_cmd(data, sel, dummy_len=0, read_len=0):
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

def spi_cmd2(data, data2, sel):
    sel.off()
    spi.write(bytearray(data))
    spi.write(data2)
    sel.on()

buf = bytearray(8)

for ram in (ram_a_sel, ram_b_sel):
    for j in range(1024):
        addr = random.randint(0, 0x100000)
        for i in range(8):
            buf[i] = random.randint(0, 255)

        spi_cmd2([CMD_WRITE, addr >> 16, (addr >> 8) & 0xFF, addr & 0xFF], buf, ram)
        data = spi_cmd([CMD_READ, addr >> 16, (addr >> 8) & 0xFF, addr & 0xFF], ram, 0, 8)

        for i in range(8):
            if buf[i] != data[i]:
                raise Exception(f"Error {} != {} at addr {addr}+{i}")
