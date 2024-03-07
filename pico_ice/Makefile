# Project setup
PROJ      = tinyqv

# Files
FILES = pico_ice.v ../cpu/*.v ../peri/uart/*.v ../peri/spi/*.v

.PHONY: pico_ice clean burn

pico_ice:
	# Lint
	#verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-MULTITOP $(FILES)

	# synthesize using Yosys
	yosys -p "synth_ice40 -abc9 -device u -top tinyQV_top -json $(PROJ).json" -DICE40 $(FILES) > yosys.log
	@grep Warn yosys.log || true
	@grep Error yosys.log || true
	@grep "   Number of cells" yosys.log
	@grep "     SB_DFF" yosys.log | awk '{sum+=$$2;}END{printf("     SB_DFF* %25d\n", sum);}'
	@grep "     SB_LUT" yosys.log
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
	@grep "   Number of cells" yosys.log | awk '{printf("| Cells | %s |\n", $$4);}'
	@grep "     SB_DFF" yosys.log | awk '{sum+=$$2;}END{printf("| SB_DFF* | %d |\n", sum);}'
	@grep "     SB_LUT" yosys.log | awk '{printf("| %s | %s |\n", $$1, $$2);}'
	@grep "     ICESTORM_LC" nextpnr.log | awk '{gsub(/\//, "", $$3);printf("| ICE40 LCs | %s |\n", $$3);}'

clean:
	rm $(PROJ).asc $(PROJ).bin $(PROJ).json
