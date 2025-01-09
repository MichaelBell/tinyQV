.PHONY: all

%-results.xml:
	make -f test_$*.mk clean
	make -f test_$*.mk
	mv results.xml $@

%-results-32.xml:
	make XLEN=32 -f test_$*.mk clean
	make XLEN=32 -f test_$*.mk
	mv results.xml $@

%-results-64.xml:
	make XLEN=64 -f test_$*.mk clean
	make XLEN=64 -f test_$*.mk
	mv results.xml $@

all: clean alu-results.xml core-results.xml counter-results.xml cpu-results.xml decode-results-32.xml decode-results-64.xml mem_ctrl-results.xml qspi_ctrl-results.xml register-results.xml

clean:
	rm *results.xml *results-32.xml *results-64.xml || true
