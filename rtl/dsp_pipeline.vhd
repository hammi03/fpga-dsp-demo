-- =============================================================================
-- dsp_pipeline.vhd
-- Signal Processing Pipeline: FIR Low-Pass Filter -> Threshold Detector
--
-- Connects fir_filter and threshold_detector into a two-stage pipeline.
-- The filtered signal and the detection flag are both available as outputs
-- so they can be observed independently in simulation and on hardware.
--
-- Data flow:
--   data_in --> [fir_filter] --> filtered_out --> [threshold_detector] --> detected
--
-- Latency: 2 clock cycles (1 per stage)
--
-- Generics:
--   TAPS        : FIR tap count
--   DATA_BITS   : word width throughout the pipeline
--   SCALE_SHIFT : FIR coefficient scaling exponent
--   THRESHOLD   : detection threshold for |filtered_out|
--
-- Standard: IEEE 1076-2008
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dsp_pipeline is
    generic (
        TAPS        : integer := 8;
        DATA_BITS   : integer := 16;
        SCALE_SHIFT : integer := 8;
        THRESHOLD   : integer := 500
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        data_in      : in  signed(DATA_BITS-1 downto 0);
        valid_in     : in  std_logic;
        filtered_out : out signed(DATA_BITS-1 downto 0);  -- FIR output
        detected     : out std_logic;                      -- threshold flag
        valid_out    : out std_logic                       -- aligned with detected
    );
end entity dsp_pipeline;

architecture rtl of dsp_pipeline is

    -- Internal wire between the two stages
    signal fir_out   : signed(DATA_BITS-1 downto 0);
    signal fir_valid : std_logic;

begin

    -- Stage 1: FIR low-pass filter
    fir : entity work.fir_filter
        generic map (
            TAPS        => TAPS,
            DATA_BITS   => DATA_BITS,
            SCALE_SHIFT => SCALE_SHIFT
        )
        port map (
            clk       => clk,
            rst       => rst,
            data_in   => data_in,
            valid_in  => valid_in,
            data_out  => fir_out,
            valid_out => fir_valid
        );

    -- Drive filtered_out directly from FIR stage
    filtered_out <= fir_out;

    -- Stage 2: Threshold detector
    det : entity work.threshold_detector
        generic map (
            DATA_BITS => DATA_BITS,
            THRESHOLD => THRESHOLD
        )
        port map (
            clk       => clk,
            rst       => rst,
            data_in   => fir_out,
            valid_in  => fir_valid,
            detected  => detected,
            valid_out => valid_out
        );

end architecture rtl;
