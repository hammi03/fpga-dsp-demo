GHDL     = ghdl
STD      = --std=08
WORKDIR  = work
VCDFILE  = results/sim.vcd

RTL = rtl/fir_filter.vhd
TB  = tb/tb_fir_filter.vhd

.PHONY: all sim clean wave

all: sim

sim:
	$(GHDL) -a $(STD) $(RTL) $(TB)
	$(GHDL) -e $(STD) tb_fir_filter
	$(GHDL) -r $(STD) tb_fir_filter --vcd=$(VCDFILE) --stop-time=3us

wave:
	gtkwave $(VCDFILE) &

clean:
	rm -f *.cf *.o e~* tb_fir_filter $(VCDFILE)
