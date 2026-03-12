GHDL    = ghdl
STD     = --std=08

RTL_FIR      = rtl/fir_filter.vhd
RTL_DET      = rtl/threshold_detector.vhd
RTL_PIPELINE = rtl/dsp_pipeline.vhd
TB_FIR       = tb/tb_fir_filter.vhd
TB_PIPELINE  = tb/tb_dsp_pipeline.vhd

VCD_FIR      = results/sim.vcd
VCD_PIPELINE = results/sim_pipeline.vcd

.PHONY: all sim sim-pipeline clean wave wave-pipeline

all: sim sim-pipeline

sim:
	$(GHDL) -a $(STD) $(RTL_FIR) $(TB_FIR)
	$(GHDL) -e $(STD) tb_fir_filter
	$(GHDL) -r $(STD) tb_fir_filter --vcd=$(VCD_FIR) --stop-time=3us

sim-pipeline:
	$(GHDL) -a $(STD) $(RTL_FIR) $(RTL_DET) $(RTL_PIPELINE) $(TB_PIPELINE)
	$(GHDL) -e $(STD) tb_dsp_pipeline
	$(GHDL) -r $(STD) tb_dsp_pipeline --vcd=$(VCD_PIPELINE) --stop-time=10us

wave:
	gtkwave $(VCD_FIR) &

wave-pipeline:
	gtkwave $(VCD_PIPELINE) &

clean:
	rm -f *.cf *.o e~* tb_fir_filter tb_dsp_pipeline $(VCD_FIR) $(VCD_PIPELINE)
