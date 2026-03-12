-- =============================================================================
-- tb_matched_filter.vhd
-- Testbench for matched_filter
--
-- Template: T = [0, 50, 150, 250, 100, 0, 0, 0]
-- Expected peak (template input): 380  (= 97500 >> 8)
--
-- Tests:
--   1. Template input  -> peak_out = 380  (100% match)
--   2. Flat pulse      -> peak_out = 322  (84.7%)  below-threshold vs template
--   3. Alternating noise -> peak_out <= 60  (clearly suppressed)
--   4. Reversed template -> peak_out = 361  (95%)  lower than forward match
--
-- Self-checking: each test reports PASS or FAIL via severity note / error.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_matched_filter is
end entity tb_matched_filter;

architecture sim of tb_matched_filter is

    constant CLK_PERIOD  : time    := 10 ns;
    constant DATA_BITS   : integer := 16;
    constant SCALE_SHIFT : integer := 8;
    constant PEAK_THEORY : integer := 380;   -- 97500 >> 8

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal data_in   : signed(DATA_BITS-1 downto 0) := (others => '0');
    signal valid_in  : std_logic := '0';
    signal data_out  : signed(DATA_BITS-1 downto 0);
    signal valid_out : std_logic;

    signal sim_done  : boolean := false;

    -- -------------------------------------------------------------------------
    -- Send one sample and wait for one rising clock edge
    -- -------------------------------------------------------------------------
    procedure send(
        signal din : out signed(DATA_BITS-1 downto 0);
        signal vin : out std_logic;
        constant v : in  integer
    ) is begin
        din <= to_signed(v, DATA_BITS);
        vin <= '1';
        wait until rising_edge(clk);
    end procedure;

    -- -------------------------------------------------------------------------
    -- Check that the absolute value of data_out equals expected (+-1 tolerance)
    -- -------------------------------------------------------------------------
    procedure check_output(
        signal   dout : in signed(DATA_BITS-1 downto 0);
        constant exp  : in integer;
        constant msg  : in string
    ) is
        variable got : integer;
    begin
        wait for 1 ns;   -- settle after clock edge
        got := to_integer(dout);
        if got = exp then
            report "PASS  " & msg &
                   "  out=" & integer'image(got)
                severity note;
        else
            report "FAIL  " & msg &
                   "  got=" & integer'image(got) &
                   "  expected=" & integer'image(exp)
                severity error;
        end if;
    end procedure;

    -- -------------------------------------------------------------------------
    -- Check that peak of last window is at least min_peak (>=) or at most
    -- max_peak (<=); use -1 to disable a bound.
    -- -------------------------------------------------------------------------
    procedure check_peak_range(
        constant peak    : in integer;
        constant min_val : in integer;
        constant max_val : in integer;
        constant msg     : in string
    ) is begin
        if (min_val = -1 or peak >= min_val) and
           (max_val = -1 or peak <= max_val) then
            report "PASS  " & msg &
                   "  peak=" & integer'image(peak)
                severity note;
        else
            report "FAIL  " & msg &
                   "  peak=" & integer'image(peak) &
                   "  expected in [" &
                   integer'image(min_val) & "," &
                   integer'image(max_val) & "]"
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

    dut : entity work.matched_filter
        generic map (
            DATA_BITS   => DATA_BITS,
            SCALE_SHIFT => SCALE_SHIFT
        )
        port map (
            clk       => clk,
            rst       => rst,
            data_in   => data_in,
            valid_in  => valid_in,
            data_out  => data_out,
            valid_out => valid_out
        );

    stim_proc : process
        variable win_peak : integer;
    begin
        -- Reset
        rst      <= '1';
        valid_in <= '0';
        wait for 5 * CLK_PERIOD;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);

        -- ==================================================================
        -- Test 1: Template input -> peak output must equal PEAK_THEORY (380)
        --
        -- Template T = [0, 50, 150, 250, 100, 0, 0, 0]
        -- The filter needs TAPS=8 samples to fully overlap with the template.
        -- After sending all 8 template samples, the next output is the peak.
        -- We send the template (8 samples) followed by 7 zeros to flush the
        -- pipeline, then capture the maximum output seen.
        --
        --   Sample  data_in  mf_out (after 1-cycle latency)
        --     0       0         0
        --     1      50         0
        --     2     150         0
        --     3     250       (partial overlap)
        --     4     100       (partial overlap)
        --     5       0       (partial overlap)
        --     6       0       (partial overlap)
        --     7       0       380  <- full overlap at this cycle
        --     8       0       ...
        -- ==================================================================
        report "--- Test 1: Template input (expected peak = 380) ---"
            severity note;

        win_peak := 0;

        -- Send template
        send(data_in, valid_in,   0);
        send(data_in, valid_in,  50);
        send(data_in, valid_in, 150);
        send(data_in, valid_in, 250);
        send(data_in, valid_in, 100);
        send(data_in, valid_in,   0);
        send(data_in, valid_in,   0);
        send(data_in, valid_in,   0);

        -- Flush: 7 more zeros; capture maximum data_out seen
        for k in 0 to 6 loop
            wait for 1 ns;
            if to_integer(data_out) > win_peak then
                win_peak := to_integer(data_out);
            end if;
            send(data_in, valid_in, 0);
        end loop;
        wait for 1 ns;
        if to_integer(data_out) > win_peak then
            win_peak := to_integer(data_out);
        end if;

        check_peak_range(win_peak, PEAK_THEORY, PEAK_THEORY,
                         "Template input peak");

        valid_in <= '0';
        wait for 3 * CLK_PERIOD;

        -- ==================================================================
        -- Test 2: Flat pulse [150*8] -> peak must be less than template peak
        -- Python model predicts 322 (84.7% of 380).
        -- ==================================================================
        report "--- Test 2: Flat pulse (expected peak = 322) ---"
            severity note;

        win_peak := 0;
        for k in 0 to 7 loop
            send(data_in, valid_in, 150);
        end loop;
        for k in 0 to 6 loop
            wait for 1 ns;
            if to_integer(data_out) > win_peak then
                win_peak := to_integer(data_out);
            end if;
            send(data_in, valid_in, 0);
        end loop;
        wait for 1 ns;
        if to_integer(data_out) > win_peak then
            win_peak := to_integer(data_out);
        end if;

        check_peak_range(win_peak, 310, 335,
                         "Flat pulse peak (expected ~322)");

        valid_in <= '0';
        wait for 3 * CLK_PERIOD;

        -- ==================================================================
        -- Test 3: Alternating noise [100,-100,100,...] -> strongly suppressed
        -- Python model predicts peak = 59 (15.5% of 380).
        -- ==================================================================
        report "--- Test 3: Alternating noise (expected peak <= 70) ---"
            severity note;

        win_peak := 0;
        for k in 0 to 7 loop
            if k mod 2 = 0 then
                send(data_in, valid_in, 100);
            else
                send(data_in, valid_in, -100);
            end if;
        end loop;
        for k in 0 to 6 loop
            wait for 1 ns;
            if abs(to_integer(data_out)) > win_peak then
                win_peak := abs(to_integer(data_out));
            end if;
            send(data_in, valid_in, 0);
        end loop;
        wait for 1 ns;
        if abs(to_integer(data_out)) > win_peak then
            win_peak := abs(to_integer(data_out));
        end if;

        check_peak_range(win_peak, -1, 70,
                         "Alternating noise peak (expected <= 70)");

        valid_in <= '0';
        wait for 3 * CLK_PERIOD;

        -- ==================================================================
        -- Test 4: Reversed template [0,0,0,100,250,150,50,0] -> lower than
        -- forward match.  Python model predicts 361 (95%); strict upper
        -- bound = PEAK_THEORY - 1 = 379.
        -- ==================================================================
        report "--- Test 4: Reversed template (expected peak < 380) ---"
            severity note;

        win_peak := 0;
        -- Reversed template: [0, 0, 0, 100, 250, 150, 50, 0]
        send(data_in, valid_in,   0);
        send(data_in, valid_in,   0);
        send(data_in, valid_in,   0);
        send(data_in, valid_in, 100);
        send(data_in, valid_in, 250);
        send(data_in, valid_in, 150);
        send(data_in, valid_in,  50);
        send(data_in, valid_in,   0);
        for k in 0 to 6 loop
            wait for 1 ns;
            if to_integer(data_out) > win_peak then
                win_peak := to_integer(data_out);
            end if;
            send(data_in, valid_in, 0);
        end loop;
        wait for 1 ns;
        if to_integer(data_out) > win_peak then
            win_peak := to_integer(data_out);
        end if;

        check_peak_range(win_peak, 350, PEAK_THEORY - 1,
                         "Reversed template peak (expected ~361, < 380)");

        valid_in <= '0';

        -- ==================================================================
        -- Done
        -- ==================================================================
        wait for 5 * CLK_PERIOD;
        report "=== Matched filter simulation complete ===" severity note;
        sim_done <= true;
        wait;

    end process stim_proc;

end architecture sim;
