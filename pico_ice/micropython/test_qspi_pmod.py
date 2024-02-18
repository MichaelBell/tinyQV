import time
from machine import SPI, Pin, PWM
machine.freq(133_000_000)

for i in range(30):
    Pin(i, Pin.IN, pull=None)

flash_sel = Pin(9, Pin.IN, Pin.PULL_UP)
ice_creset_b = machine.Pin(27, machine.Pin.OUT)
ice_creset_b.value(0)
clk = PWM(Pin(24), freq=8_000_000, duty_u16=32768)

spi = SPI(0, 16_000_000, sck=Pin(2), mosi=Pin(3), miso=Pin(0))

flash_sel = Pin(1, Pin.OUT)
ram_a_sel = Pin(4, Pin.OUT)
ram_b_sel = Pin(6, Pin.OUT)

flash_sel.on()
ram_a_sel.on()
ram_b_sel.on()

print("Flash ID")

buf = bytearray(2)
flash_sel.off()
spi.write(b'\x90\x00\x00\x00')
spi.readinto(buf)
flash_sel.on()
for b in buf: print("%02x " % (b,), end="")
print()

buf = bytearray(3)
flash_sel.off()
spi.write(b'\x9f')
spi.readinto(buf)
flash_sel.on()

for b in buf: print("%02x " % (b,), end="")
print()

print("RAM A ID")
buf = bytearray(8)
ram_a_sel.off()
spi.write(b'\x9f\x00\x00\x00')
spi.readinto(buf)
ram_a_sel.on()
for b in buf: print("%02x " % (b,), end="")
print()

print("RAM B ID")
buf = bytearray(8)
ram_b_sel.off()
spi.write(b'\x9f\x00\x00\x00')
spi.readinto(buf)
ram_b_sel.on()
for b in buf: print("%02x " % (b,), end="")
print()

if True:
    spi = SPI(1, 16_000_000)

    flash_sel = Pin(9, Pin.OUT)
    ram_sel = Pin(14, Pin.OUT)

    flash_sel.on()
    ram_sel.off()

    print("Flash ID")

    buf = bytearray(2)
    flash_sel.off()
    spi.write(b'\xAB')
    flash_sel.on()
    time.sleep(1)
    flash_sel.off()
    spi.write(b'\x90\x00\x00\x00')
    spi.readinto(buf)
    flash_sel.on()
    for b in buf: print("%02x " % (b,), end="")
    print()

    buf = bytearray(3)
    flash_sel.off()
    spi.write(b'\x9f')
    spi.readinto(buf)
    flash_sel.on()

    for b in buf: print("%02x " % (b,), end="")
    print()

    print("RAM A ID")
    buf = bytearray(8)
    ram_sel.on()
    spi.write(b'\x9f\x00\x00\x00')
    spi.readinto(buf)
    ram_sel.off()
    for b in buf: print("%02x " % (b,), end="")
    print()

