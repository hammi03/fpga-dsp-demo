-- =============================================================================
-- threshold_detector.vhd
-- Amplitude Threshold Detector
--
-- Asserts detected='1' for one clock cycle whenever the absolute value of
-- the input sample exceeds THRESHOLD.  Designed to follow a FIR filter in
-- a signal-processing pipeline.
--
-- Generics:
--   DATA_BITS : input word width (must match upstream FIR filter)
--   THRESHOLD : detection threshold (compared against |data_in|; same unit as data_in)
--
-- Ports:
--   clk       : system clock (rising edge active)
--   rst       : synchronous reset, active high
--   data_in   : signed input sample (from FIR filter output)
--   valid_in  : '1' when data_in holds a valid sample
--   detected  : '1' for one cycle when |data_in| > THRESHOLD; '0' otherwise
--   valid_out : follows valid_in (pipeline handshake)
--
-- Note: detected is updated every clock cycle regardless of valid_in.
--       valid_out indicates when the result is meaningful downstream.
-- Latency: 1 clock cycle
-- Standard: IEEE 1076-2008
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity threshold_detector is
    generic (
        DATA_BITS : integer := 16;
        THRESHOLD : integer := 500    -- default: trigger above half full-scale
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        data_in   : in  signed(DATA_BITS-1 downto 0);
        valid_in  : in  std_logic;
        detected  : out std_logic;
        valid_out : out std_logic
    );
end entity threshold_detector;

architecture rtl of threshold_detector is

    -- Compute absolute value of a signed number in two's complement:
    --   abs(x) = x       if x >= 0
    --   abs(x) = -x      if x <  0
    -- We need DATA_BITS+1 bits for abs to avoid overflow at -32768.
    constant ABS_BITS : integer := DATA_BITS + 1;

begin

    det_proc : process(clk)
        variable abs_val : signed(ABS_BITS-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                detected  <= '0';
                valid_out <= '0';
            else
                -- Compute |data_in| with one extra bit to handle min negative
                if data_in(DATA_BITS-1) = '1' then
                    abs_val := -resize(data_in, ABS_BITS);
                else
                    abs_val :=  resize(data_in, ABS_BITS);
                end if;

                -- Compare magnitude against threshold
                if abs_val > to_signed(THRESHOLD, ABS_BITS) then
                    detected <= '1';
                else
                    detected <= '0';
                end if;

                valid_out <= valid_in;
            end if;
        end if;
    end process det_proc;

end architecture rtl;
