import machine #from machine import Pin, Timer
import utime

ice_creset_b = machine.Pin(27, machine.Pin.OUT)
ice_creset_b.value(0)

ice_ssn = machine.Pin(17, machine.Pin.OUT)
ice_ssn.value(0)

ice_done = machine.Pin(26, machine.Pin.IN)
ice_sck = machine.Pin(10, machine.Pin.OUT)
ice_sck.value(1)
ice_si = machine.Pin(8, machine.Pin.OUT)

utime.sleep_us(1) # wait at least 200ns
ice_creset_b.value(1)

utime.sleep_us(1200) # wait at least 1200us

ice_ssn.value(1)
for i in range(8): # 8 dummy clocks
    ice_sck.value(0)
    utime.sleep_us(1)
    ice_sck.value(1)
    utime.sleep_us(1)

ice_ssn.value(0)

fid = open('myfpga_impl_1.bin','rb')
fid.seek(0, 2)
filelength = fid.tell()
fid.seek(0, 0)

counter=0
while True:
    ch = fid.read(1)
    counter+=1
    if (counter%10000)==0:
        print(f"{counter*100/filelength:.1f}%")
    if ch != b"":
        value = int.from_bytes(ch, 'big')
        bits = [int(c) for c in f"{value:08b}"]
        for i in range(8):
            ice_sck.value(0)
            ice_si.value(bits[i])
            ice_sck.value(1)
    else:
        break
print("DONE")

ice_ssn.value(1)
utime.sleep_us(1)

for i in range(200):
    ice_sck.value(0)
    ice_sck.value(1)
  
print(f"{ice_done.value()=}")

led_r = machine.Pin(4, machine.Pin.OUT) # Mapped through test-FPGA to control LED
led_g = machine.Pin(6, machine.Pin.OUT)
led_b = machine.Pin(7, machine.Pin.OUT)

for i in range(100):
    led_r.value(i%3==0)
    led_g.value(i%3==1)
    led_b.value(i%3==2)
    utime.sleep_ms(500)