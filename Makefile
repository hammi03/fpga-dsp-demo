GHDL    = ghdl
STD     = --std=08

RTL_PKG      = rtl/dsp_config_pkg.vhd
RTL_FIR      = rtl/fir_filter.vhd
RTL_DET      = rtl/threshold_detector.vhd
RTL_PEAK     = rtl/peak_detector.vhd
RTL_PIPELINE = rtl/dsp_pipeline.vhd
RTL_MF       = rtl/matched_filter.vhd
RTL_FULL     = rtl/full_pipeline.vhd
TB_FIR       = tb/tb_fir_filter.vhd
TB_PIPELINE  = tb/tb_dsp_pipeline.vhd
TB_PEAK      = tb/tb_peak_detector.vhd
TB_MF        = tb/tb_matched_filter.vhd
TB_FULL      = tb/tb_full_pipeline.vhd

VCD_FIR      = results/sim.vcd
VCD_PIPELINE = results/sim_pipeline.vcd
VCD_PEAK     = results/sim_peak.vcd
VCD_MF       = results/sim_mf.vcd
VCD_FULL     = results/sim_full.vcd

.PHONY: all sim sim-pipeline sim-peak sim-mf sim-full clean wave wave-pipeline wave-peak wave-mf wave-full

all: sim sim-pipeline sim-peak sim-mf sim-full

sim:
	$(GHDL) -a $(STD) $(RTL_FIR) $(TB_FIR)
	$(GHDL) -e $(STD) tb_fir_filter
	$(GHDL) -r $(STD) tb_fir_filter --vcd=$(VCD_FIR) --stop-time=3us

sim-pipeline:
	$(GHDL) -a $(STD) $(RTL_FIR) $(RTL_DET) $(RTL_PIPELINE) $(TB_PIPELINE)
	$(GHDL) -e $(STD) tb_dsp_pipeline
	$(GHDL) -r $(STD) tb_dsp_pipeline --vcd=$(VCD_PIPELINE) --stop-time=10us

sim-peak:
	$(GHDL) -a $(STD) $(RTL_PEAK) $(TB_PEAK)
	$(GHDL) -e $(STD) tb_peak_detector
	$(GHDL) -r $(STD) tb_peak_detector --vcd=$(VCD_PEAK) --stop-time=5us

sim-mf:
	$(GHDL) -a $(STD) $(RTL_MF) $(TB_MF)
	$(GHDL) -e $(STD) tb_matched_filter
	$(GHDL) -r $(STD) tb_matched_filter --vcd=$(VCD_MF) --stop-time=5us

wave:
	gtkwave $(VCD_FIR) &

wave-pipeline:
	gtkwave $(VCD_PIPELINE) &

wave-peak:
	gtkwave $(VCD_PEAK) &

sim-full:
	$(GHDL) -a $(STD) $(RTL_PKG) $(RTL_FIR) $(RTL_DET) $(RTL_PEAK) $(RTL_MF) $(RTL_FULL) $(TB_FULL)
	$(GHDL) -e $(STD) tb_full_pipeline
	$(GHDL) -r $(STD) tb_full_pipeline --vcd=$(VCD_FULL) --stop-time=10us

wave-mf:
	gtkwave $(VCD_MF) &

wave-full:
	gtkwave $(VCD_FULL) &

clean:
	rm -f *.cf *.o e~* tb_fir_filter tb_dsp_pipeline tb_peak_detector tb_matched_filter tb_full_pipeline \
	      $(VCD_FIR) $(VCD_PIPELINE) $(VCD_PEAK) $(VCD_MF) $(VCD_FULL)
