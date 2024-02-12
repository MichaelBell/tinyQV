.PHONY: all

%-results.xml:
	make -f test_$*.mk clean
	make -f test_$*.mk
	mv results.xml $@

all: clean alu-results.xml core-results.xml counter-results.xml cpu-results.xml decode-results.xml mem_ctrl-results.xml qspi_ctrl-results.xml register-results.xml

clean:
	rm *results.xml || true