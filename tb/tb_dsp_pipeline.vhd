-- =============================================================================
-- tb_dsp_pipeline.vhd
-- Testbench for dsp_pipeline (FIR filter + threshold detector)
--
-- Tests:
--   1. No detection during silence (all zeros)
--   2. No detection for a weak signal below threshold
--   3. Detection for a strong DC signal above threshold
--   4. No detection after FIR has suppressed a Nyquist-frequency signal
--      (demonstrates filter + detector working together: high-freq noise
--       that would trigger the detector raw is killed by the filter first)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_dsp_pipeline is
end entity tb_dsp_pipeline;

architecture sim of tb_dsp_pipeline is

    constant CLK_PERIOD : time    := 10 ns;
    constant THRESHOLD  : integer := 500;   -- must match generic below

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal data_in      : signed(15 downto 0) := (others => '0');
    signal valid_in     : std_logic := '0';
    signal filtered_out : signed(15 downto 0);
    signal detected     : std_logic;
    signal valid_out    : std_logic;

    signal sim_done     : boolean := false;

    procedure check_det(
        signal   det      : in std_logic;
        constant expected : in std_logic;
        constant msg      : in string
    ) is begin
        if det = expected then
            report "PASS  " & msg severity note;
        else
            report "FAIL  " & msg &
                   "  got=" & std_logic'image(det) &
                   "  expected=" & std_logic'image(expected)
                severity error;
        end if;
    end procedure;

begin

    clk_proc : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    dut : entity work.dsp_pipeline
        generic map (
            TAPS        => 8,
            DATA_BITS   => 16,
            SCALE_SHIFT => 8,
            THRESHOLD   => THRESHOLD
        )
        port map (
            clk          => clk,
            rst          => rst,
            data_in      => data_in,
            valid_in     => valid_in,
            filtered_out => filtered_out,
            detected     => detected,
            valid_out    => valid_out
        );

    stim_proc : process
    begin
        -- Reset
        rst      <= '1';
        valid_in <= '0';
        data_in  <= (others => '0');
        wait for 5 * CLK_PERIOD;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);

        -- ==================================================================
        -- Test 1: Silence -> no detection
        -- Send 20 zero samples; detected must stay '0' throughout.
        -- Pipeline latency is 2 cycles, so check from cycle 3 onward.
        -- ==================================================================
        report "--- Test 1: Silence (no detection) ---" severity note;

        data_in  <= to_signed(0, 16);
        valid_in <= '1';
        for i in 0 to 19 loop
            wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check_det(detected, '0', "Silence: detected = 0");

        valid_in <= '0';
        wait for 3 * CLK_PERIOD;

        -- ==================================================================
        -- Test 2: Weak DC signal (200) below threshold (500) -> no detection
        -- ==================================================================
        report "--- Test 2: Weak DC (200 < 500) -> no detection ---" severity note;

        data_in  <= to_signed(200, 16);
        valid_in <= '1';
        for i in 0 to 15 loop
            wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check_det(detected, '0', "Weak DC 200: detected = 0");

        valid_in <= '0';
        wait for 3 * CLK_PERIOD;

        -- ==================================================================
        -- Test 3: Strong DC signal (1000) above threshold (500) -> detection
        -- FIR steady-state output = 1000 (unity DC gain), so |out| = 1000 > 500
        -- ==================================================================
        report "--- Test 3: Strong DC (1000 > 500) -> detection ---" severity note;

        data_in  <= to_signed(1000, 16);
        valid_in <= '1';
        -- Fill FIR (8 cycles) + detector latency (1 cycle) = 9 cycles minimum
        for i in 0 to 12 loop
            wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check_det(detected, '1', "Strong DC 1000: detected = 1");

        valid_in <= '0';
        data_in  <= (others => '0');
        wait for 5 * CLK_PERIOD;

        -- ==================================================================
        -- Test 4: Nyquist noise (+-1000) -> FIR suppresses to 0 -> no detection
        -- Raw amplitude (1000) would exceed threshold, but after filtering
        -- the output is 0 (complete Nyquist rejection), so no detection.
        -- This is the key demonstration of filter + detector working together.
        -- ==================================================================
        report "--- Test 4: Nyquist noise (raw 1000, filtered 0) -> no detection ---" severity note;

        valid_in <= '1';
        for i in 0 to 23 loop
            if (i mod 2) = 0 then
                data_in <= to_signed(1000, 16);
            else
                data_in <= to_signed(-1000, 16);
            end if;
            wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check_det(detected, '0', "Nyquist +-1000 filtered to 0: detected = 0");

        valid_in <= '0';

        -- ==================================================================
        -- Done
        -- ==================================================================
        wait for 5 * CLK_PERIOD;
        report "=== Pipeline simulation complete ===" severity note;
        sim_done <= true;
        wait;

    end process stim_proc;

end architecture sim;
