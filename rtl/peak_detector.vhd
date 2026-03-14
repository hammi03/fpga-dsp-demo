-- =============================================================================
-- peak_detector.vhd
-- Peak Detector with State Machine
--
-- Monitors a signed input stream and finds the sample with the largest
-- absolute value within a detection window (signal above THRESHOLD).
-- Reports the peak value and its 0-based cycle position when the signal
-- falls back below THRESHOLD.
--
-- State machine (two states; DONE is merged into TRACKING for lower latency):
--   IDLE     : waiting for |data_in| > THRESHOLD
--   TRACKING : signal is above threshold; track running maximum;
--              when signal drops below threshold, output peak and return to IDLE
--
-- Outputs:
--   peak_val   : signed value of the sample with the largest |amplitude|
--   peak_pos   : position (0-based cycle index within the detection window)
--   peak_valid : '1' for exactly one clock cycle when peak_val/peak_pos are valid
--
-- Generics:
--   DATA_BITS : word width (must match upstream FIR filter)
--   THRESHOLD : detection threshold for |data_in|
--   POS_BITS  : width of the position counter (max window = 2^POS_BITS cycles)
--
-- Latency to first peak_valid pulse: variable; minimum 3 cycles
--   (1 cycle to enter TRACKING + 1 sample above threshold + 1 cycle to exit)
-- Standard: IEEE 1076-2008
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity peak_detector is
    generic (
        DATA_BITS : integer := 16;
        THRESHOLD : integer := 500;
        POS_BITS  : integer := 16
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        data_in    : in  signed(DATA_BITS-1 downto 0);
        valid_in   : in  std_logic;
        peak_val   : out signed(DATA_BITS-1 downto 0);
        peak_pos   : out unsigned(POS_BITS-1 downto 0);
        peak_valid : out std_logic
    );
end entity peak_detector;

architecture rtl of peak_detector is

    -- One extra bit to handle abs(-32768) without overflow
    constant ABS_BITS : integer := DATA_BITS + 1;

    -- State machine (two states: DONE is merged into TRACKING for lower latency)
    type state_t is (IDLE, TRACKING);
    signal state : state_t := IDLE;

    -- Running peak registers
    signal max_val : signed(DATA_BITS-1 downto 0)  := (others => '0');
    signal max_abs : signed(ABS_BITS-1 downto 0)   := (others => '0');
    signal max_pos : unsigned(POS_BITS-1 downto 0) := (others => '0');
    signal pos_cnt : unsigned(POS_BITS-1 downto 0) := (others => '0');

    -- Helper: absolute value of data_in in ABS_BITS
    signal abs_in : signed(ABS_BITS-1 downto 0);

begin

    -- Combinatorial absolute value
    abs_in <= resize(data_in, ABS_BITS) when data_in(DATA_BITS-1) = '0'
         else -resize(data_in, ABS_BITS);

    peak_proc : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state      <= IDLE;
                max_val    <= (others => '0');
                max_abs    <= (others => '0');
                max_pos    <= (others => '0');
                pos_cnt    <= (others => '0');
                peak_val   <= (others => '0');
                peak_pos   <= (others => '0');
                peak_valid <= '0';

            else
                -- Default: peak_valid is a one-cycle pulse
                peak_valid <= '0';

                case state is

                    -- ---------------------------------------------------------
                    when IDLE =>
                        -- Wait for signal to rise above threshold
                        if valid_in = '1' and abs_in > to_signed(THRESHOLD, ABS_BITS) then
                            -- First sample of the detection window (position 0)
                            max_val <= data_in;
                            max_abs <= abs_in;
                            max_pos <= (others => '0');  -- this sample is at position 0
                            pos_cnt <= to_unsigned(1, POS_BITS);  -- next sample will be at position 1
                            state   <= TRACKING;
                        end if;

                    -- ---------------------------------------------------------
                    when TRACKING =>
                        if valid_in = '1' then
                            if abs_in > to_signed(THRESHOLD, ABS_BITS) then
                                -- Still inside detection window: update running max
                                if abs_in > max_abs then
                                    max_val <= data_in;
                                    max_abs <= abs_in;
                                    max_pos <= pos_cnt;
                                end if;
                                pos_cnt <= pos_cnt + 1;
                            else
                                -- Signal dropped below threshold: output peak
                                -- immediately (same registered cycle, no extra state)
                                peak_val   <= max_val;
                                peak_pos   <= max_pos;
                                peak_valid <= '1';
                                state      <= IDLE;
                            end if;
                        end if;

                end case;
            end if;
        end if;
    end process peak_proc;

end architecture rtl;
