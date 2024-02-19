import time
import random
import rp2
from machine import UART, Pin, PWM

for i in range(30):
    Pin(i, Pin.IN, pull=None)

flash_sel = Pin(9, Pin.IN, Pin.PULL_UP)
ice_creset_b = machine.Pin(27, machine.Pin.OUT)
ice_creset_b.value(0)

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
    sm.put(0b11111001)
    sm.put(0b11111001)
    
    sm.put(0b01010110)  # Directions
    
    for i in range(num_bytes*2 + 4):
        buf[i] = sm.get()
        
    sm.put(0b11111111)
    sm.put(0b01010110)  # Directions

    return buf

def read_data_enable_cm(num_bytes):
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
    #sm.put(0b01010000)
    
    sm.put(0b01010110)  # Directions
    
    for i in range(num_bytes*2 + 4):
        buf[i] = sm.get()
        
    sm.put(0b11111111)
    sm.put(0b01010110)  # Directions

    return buf

def read_data_cm(num_bytes, exit_cm=False):
    buf = bytearray(num_bytes*2 + 4)
    
    sm.put(6+2-1)     # Address + Dummy - 1
    sm.put(num_bytes*2 + 4 - 1) # Data + Dummy - 1
    sm.put(0b11111111)  # Directions
    
    sm.put(0b01010000)  # Address
    sm.put(0b01010000)
    sm.put(0b01010000)
    sm.put(0b01010000)
    sm.put(0b01010000)
    sm.put(0b01010000)
    if exit_cm:
        sm.put(0b11111001) # SD3, RAM_B_SEL, SD2, RAM_A_SEL, SD0, SCK, CS, SD1
        sm.put(0b11111001)
    else:
        sm.put(0b11010001) # SD3, RAM_B_SEL, SD2, RAM_A_SEL, SD0, SCK, CS, SD1
        sm.put(0b11010001)
        #sm.put(0b01010000)
    
    sm.put(0b01010110)  # Directions
    
    for i in range(num_bytes*2 + 4):
        buf[i] = sm.get()
        
    sm.put(0b11111111)
    sm.put(0b01010110)  # Directions

    return buf

def print_bytes(data):
    for b in data: print("%02x " % (b,), end="")
    print()
    
def print_data(data):
    for i in range(len(data)):
        d = data[i]
        nibble = ((d >> 3) & 1) | ((d << 1) & 2) | ((d >> 3) & 0x4) | ((d >> 4) & 0x8)
        print("%01x" % (nibble,), end="")
        if (i & 1) != 0: print(" ", end="")
    print()
    
data = read_data(16)
print_bytes(data)
print_data(data)

data = read_data_enable_cm(16)
print_data(data)

data = read_data_cm(16)
print_data(data)

data = read_data_cm(16, True)
print_data(data)

data = read_data(16)
print_data(data)
