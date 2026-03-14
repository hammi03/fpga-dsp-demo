-- =============================================================================
-- full_pipeline.vhd
-- Unified DSP Pipeline
--
-- Connects all four processing stages into a single top-level entity:
--
--   data_in --> [FIR LP Filter] --> fir_out --> [Threshold Detector] --> detected
--                              |
--                              +--> [Matched Filter] --> mf_out --> [Peak Detector]
--                                                                      --> peak_val
--                                                                      --> peak_pos
--                                                                      --> peak_valid
--
-- The FIR low-pass filter is shared: it removes high-frequency noise once,
-- then both downstream paths operate on the clean signal independently.
--
-- Latency (cycles):
--   detected   : 2  (FIR + threshold)
--   peak_valid : variable (FIR + MF + peak state machine)
--
-- Generics:
--   DATA_BITS   : word width throughout (signed)
--   FIR_TAPS    : FIR tap count
--   FIR_SCALE   : FIR coefficient scaling exponent (2^N)
--   MF_SCALE    : Matched filter scaling exponent (2^N)
--   THRESHOLD   : |amplitude| threshold for both detectors
--   POS_BITS    : peak position counter width
--
-- Standard: IEEE 1076-2008
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity full_pipeline is
    generic (
        DATA_BITS : integer := 16;
        FIR_TAPS  : integer := 8;
        FIR_SCALE : integer := 8;
        MF_SCALE  : integer := 8;
        THRESHOLD : integer := 190;   -- half of MF peak (380/2)
        POS_BITS  : integer := 16
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        data_in    : in  signed(DATA_BITS-1 downto 0);
        valid_in   : in  std_logic;
        -- FIR output (observable for debug / downstream use)
        fir_out    : out signed(DATA_BITS-1 downto 0);
        fir_valid  : out std_logic;
        -- Threshold detector output (2-cycle latency)
        detected   : out std_logic;
        -- Matched filter + peak detector outputs (variable latency)
        peak_val   : out signed(DATA_BITS-1 downto 0);
        peak_pos   : out unsigned(POS_BITS-1 downto 0);
        peak_valid : out std_logic
    );
end entity full_pipeline;

architecture rtl of full_pipeline is

    -- Internal wires between stages
    signal fir_data  : signed(DATA_BITS-1 downto 0);
    signal fir_vld   : std_logic;

    signal mf_data   : signed(DATA_BITS-1 downto 0);
    signal mf_vld    : std_logic;

begin

    -- Drive observable outputs from internal signals
    fir_out   <= fir_data;
    fir_valid <= fir_vld;

    -- -------------------------------------------------------------------------
    -- Stage 1: FIR low-pass filter
    -- Removes high-frequency noise; output shared by both downstream stages.
    -- -------------------------------------------------------------------------
    fir : entity work.fir_filter
        generic map (
            TAPS        => FIR_TAPS,
            DATA_BITS   => DATA_BITS,
            SCALE_SHIFT => FIR_SCALE
        )
        port map (
            clk       => clk,
            rst       => rst,
            data_in   => data_in,
            valid_in  => valid_in,
            data_out  => fir_data,
            valid_out => fir_vld
        );

    -- -------------------------------------------------------------------------
    -- Stage 2a: Threshold detector
    -- Answers "is there any signal above threshold right now?" (1 bit/cycle)
    -- -------------------------------------------------------------------------
    thr : entity work.threshold_detector
        generic map (
            DATA_BITS => DATA_BITS,
            THRESHOLD => THRESHOLD
        )
        port map (
            clk       => clk,
            rst       => rst,
            data_in   => fir_data,
            valid_in  => fir_vld,
            detected  => detected,
            valid_out => open
        );

    -- -------------------------------------------------------------------------
    -- Stage 2b: Matched filter (correlator)
    -- Computes running dot-product with the template; peaks when template found.
    -- -------------------------------------------------------------------------
    mf : entity work.matched_filter
        generic map (
            DATA_BITS   => DATA_BITS,
            SCALE_SHIFT => MF_SCALE
        )
        port map (
            clk       => clk,
            rst       => rst,
            data_in   => fir_data,
            valid_in  => fir_vld,
            data_out  => mf_data,
            valid_out => mf_vld
        );

    -- -------------------------------------------------------------------------
    -- Stage 3: Peak detector
    -- Waits for MF output to exceed THRESHOLD, tracks maximum, reports on exit.
    -- -------------------------------------------------------------------------
    pk : entity work.peak_detector
        generic map (
            DATA_BITS => DATA_BITS,
            THRESHOLD => THRESHOLD,
            POS_BITS  => POS_BITS
        )
        port map (
            clk        => clk,
            rst        => rst,
            data_in    => mf_data,
            valid_in   => mf_vld,
            peak_val   => peak_val,
            peak_pos   => peak_pos,
            peak_valid => peak_valid
        );

end architecture rtl;
