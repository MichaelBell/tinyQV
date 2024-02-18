import time
import random
import rp2
from machine import UART, Pin, PWM

ice_rstn = Pin(27, Pin.OUT)
ice_rstn.off()

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
    
sm = rp2.StateMachine(0, qspi_read, 16_000_000, in_base=Pin(0), out_base=Pin(0), sideset_base=Pin(2))
sm.active(1)

def read_data(num_bytes):
    buf = bytearray(num_bytes*2 + 4)
    
    sm.put(8+6+2-1)     # Command + Address + Dummy - 1
    sm.put(num_bytes*2 + 4 - 1) # Data + Dummy - 1
    sm.put(0b11111111)  # Directions
    
    sm.put(0b11001000)  # Command
    sm.put(0b11001000)
    sm.put(0b11001000)
    sm.put(0b11000000)
    sm.put(0b11001000)
    sm.put(0b11000000)
    sm.put(0b11001000)
    sm.put(0b11001000)
    
    sm.put(0b11000000)  # Address
    sm.put(0b11000000)
    sm.put(0b11000000)
    sm.put(0b11000000)
    sm.put(0b11000000)
    sm.put(0b11000000)
    sm.put(0b11111001)
    sm.put(0b11111001)
    
    sm.put(0b11000110)  # Directions
    
    for i in range(num_bytes*2 + 4):
        buf[i] = sm.get()
        
    sm.put(0b11111111)
    sm.put(0b11000110)  # Directions

    return buf

def print_bytes(data):
    for b in data: print("%02x " % (b,), end="")
    print()
    
def print_data(data):
    for i in range(len(data)):
        d = data[i]
        nibble = ((d >> 3) & 1) | ((d << 1) & 2) | ((d >> 2) & 0xC)
        print("%01x" % (nibble,), end="")
        if (i & 1) != 0: print(" ", end="")
    print()
    
data = read_data(16)
print_bytes(data)
print_data(data)