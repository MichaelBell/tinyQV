# Project setup
PROJ      = tinyqv

# Files
FILES = pico_ice.v ../cpu/*.v ../peri/uart/*.v ../peri/spi/*.v ../peri/pwm/*.v

.PHONY: pico_ice clean burn

pico_ice:
	# Lint
	#verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-MULTITOP $(FILES)

	# synthesize using Yosys
	yosys -p "synth_ice40 -abc9 -device u -top tinyQV_top -json $(PROJ).json" -DICE40 $(FILES) > yosys.log
	@grep Warn yosys.log || true
	@grep Error yosys.log || true
	@egrep "[0-9]+ submodules" yosys.log | head -1
	@egrep "[0-9]+   SB_DFF" yosys.log | awk '{sum+=$$1;}END{printf("%9d   SB_DFF*\n", sum/2);}'
	@egrep "[0-9]+   SB_LUT" yosys.log | head -1
	@echo

	# Place and route using nextpnr
	./nextpnr.sh -r --up5k --json $(PROJ).json --package sg48 --asc $(PROJ).asc --opt-timing --pcf pico_ice.pcf
	@grep Warn nextpnr.log || true
	@grep Error nextpnr.log || true
	@grep "Max frequency.*clk" nextpnr.log | tail -1
	@echo

	# Convert to bitstream using IcePack
	icepack $(PROJ).asc $(PROJ).bin
	bin2uf2 -o $(PROJ).uf2 0x00000000 $(PROJ).bin

stats:
	@grep Warn yosys.log | grep -v tri-state || true
	@grep Error yosys.log || true
	@grep Warn nextpnr.log || true
	@grep Error nextpnr.log || true
	@grep "Max frequency.*clk" nextpnr.log | tail -1
	@echo "| Item | Count |"
	@echo "| ---- | ----- |"
	@egrep "[0-9]+ submodules" yosys.log | head -1 | awk '{printf("| Cells | %s |\n", $$1);}'
	@egrep "[0-9]+   SB_DFF" yosys.log | awk '{sum+=$$1;}END{printf("| SB_DFF* | %d |\n", sum/2);}'
	@egrep "[0-9]+   SB_LUT" yosys.log | head -1 | awk '{printf("| %s | %s |\n", $$2, $$1);}'
	@grep "     ICESTORM_LC" nextpnr.log | awk '{gsub(/\//, "", $$3);printf("| ICE40 LCs | %s |\n", $$3);}'

clean:
	rm $(PROJ).asc $(PROJ).bin $(PROJ).json
