-- =============================================================================
-- tb_fir_filter.vhd
-- Testbench for fir_filter.vhd
--
-- Tests:
--   1. Impulse Response
--      Input x[0]=256, x[1..]=0  ->  output must equal the FIR coefficients
--      [-2, 10, 44, 76, 76, 44, 10, -2]
--      (because 256 = 2^SCALE_SHIFT cancels the coefficient scaling exactly)
--
--   2. DC Response (steady-state)
--      Constant input 1000  ->  output must equal 1000 after 8 cycles
--      (unity DC gain: sum(coeffs)/256 = 256/256 = 1)
--
--   3. Nyquist-Frequency Rejection
--      Alternating +-1000  ->  output must be 0 (complete rejection at fs/2)
--
-- Simulation: GHDL
--   ghdl -a rtl/fir_filter.vhd tb/tb_fir_filter.vhd
--   ghdl -e tb_fir_filter
--   ghdl -r tb_fir_filter --vcd=results/sim.vcd --stop-time=3us
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_fir_filter is
end entity tb_fir_filter;

architecture sim of tb_fir_filter is

    -- -------------------------------------------------------------------------
    -- Component declaration
    -- -------------------------------------------------------------------------
    component fir_filter is
        generic (
            TAPS        : integer := 8;
            DATA_BITS   : integer := 16;
            SCALE_SHIFT : integer := 8
        );
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            data_in   : in  signed(DATA_BITS-1 downto 0);
            valid_in  : in  std_logic;
            data_out  : out signed(DATA_BITS-1 downto 0);
            valid_out : out std_logic
        );
    end component;

    -- -------------------------------------------------------------------------
    -- Testbench signals
    -- -------------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;   -- 100 MHz

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal data_in   : signed(15 downto 0) := (others => '0');
    signal valid_in  : std_logic := '0';
    signal data_out  : signed(15 downto 0);
    signal valid_out : std_logic;

    signal sim_done  : boolean := false;

    -- Expected impulse response (coefficient values for unit-scaled impulse)
    type int_array_t is array(0 to 7) of integer;
    constant IMPULSE_EXP : int_array_t := (-1, -6, 25, 110, 110, 25, -6, -1);

    -- -------------------------------------------------------------------------
    -- Helper: assert output value and print PASS/FAIL
    -- -------------------------------------------------------------------------
    procedure check(
        signal   dout     : in  signed(15 downto 0);
        constant expected : in  integer;
        constant msg      : in  string
    ) is
        variable got : integer;
    begin
        got := to_integer(dout);
        if got = expected then
            report "PASS  " & msg &
                   "  got=" & integer'image(got)
                severity note;
        else
            report "FAIL  " & msg &
                   "  got=" & integer'image(got) &
                   "  expected=" & integer'image(expected)
                severity error;
        end if;
    end procedure;

begin

    -- -------------------------------------------------------------------------
    -- Clock generation (stops when sim_done = true)
    -- -------------------------------------------------------------------------
    clk_proc : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- -------------------------------------------------------------------------
    -- DUT instantiation
    -- -------------------------------------------------------------------------
    dut : fir_filter
        generic map (
            TAPS        => 8,
            DATA_BITS   => 16,
            SCALE_SHIFT => 8
        )
        port map (
            clk       => clk,
            rst       => rst,
            data_in   => data_in,
            valid_in  => valid_in,
            data_out  => data_out,
            valid_out => valid_out
        );

    -- -------------------------------------------------------------------------
    -- Stimulus and self-checking
    --
    -- Timing convention:
    --   Signal changes take effect BEFORE the next rising edge.
    --   After "wait until rising_edge(clk)", the DUT has processed the input.
    --   "wait for 1 ns" lets delta cycles settle so data_out is readable.
    -- -------------------------------------------------------------------------
    stim_proc : process
    begin

        -- ----------------------------------------------------------------
        -- Reset
        -- ----------------------------------------------------------------
        rst      <= '1';
        valid_in <= '0';
        data_in  <= (others => '0');
        wait for 5 * CLK_PERIOD;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);   -- one idle cycle

        -- ================================================================
        -- Test 1: Impulse Response
        --   Send x[0]=256, then x[1..7]=0, all with valid_in='1'.
        --   Expected output: coefficients [-2, 10, 44, 76, 76, 44, 10, -2]
        --   Proof: y[n] = (sum_k coeff[k] * x[n-k]) / 256
        --          For x[0]=256, x[else]=0: y[n] = coeff[n]
        -- ================================================================
        report "--- Test 1: Impulse Response ---" severity note;

        data_in  <= to_signed(256, 16);
        valid_in <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        check(data_out, IMPULSE_EXP(0), "Impulse[0]");

        data_in <= (others => '0');
        for i in 1 to 7 loop
            wait until rising_edge(clk);
            wait for 1 ns;
            check(data_out, IMPULSE_EXP(i),
                  "Impulse[" & integer'image(i) & "]");
        end loop;

        valid_in <= '0';
        wait for 3 * CLK_PERIOD;

        -- ================================================================
        -- Test 2: DC Response
        --   Constant input 1000.  After 8 clocks all taps are filled.
        --   Expected steady-state output: 1000
        --   Proof: y = (sum(coeffs) * 1000) / 256 = (256 * 1000) / 256 = 1000
        -- ================================================================
        report "--- Test 2: DC Response (steady-state) ---" severity note;

        data_in  <= to_signed(1000, 16);
        valid_in <= '1';

        -- Fill all 8 taps
        for i in 0 to 7 loop
            wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check(data_out, 1000, "DC steady-state = 1000");

        valid_in <= '0';
        wait for 3 * CLK_PERIOD;

        -- ================================================================
        -- Test 3: Nyquist-Frequency Rejection
        --   Alternating +-1000 (= fs/2 sine wave).
        --   Expected output: 0 (complete attenuation at Nyquist)
        --   Proof: sum( coeff[k] * (-1)^k ) = -2 -10 +44 -76 +76 -44 +10 +2 = 0
        -- ================================================================
        report "--- Test 3: Nyquist-Frequency Rejection ---" severity note;

        valid_in <= '1';
        for i in 0 to 15 loop   -- 8 to fill + 8 to verify steady state
            if (i mod 2) = 0 then
                data_in <= to_signed(1000, 16);
            else
                data_in <= to_signed(-1000, 16);
            end if;
            wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        check(data_out, 0, "Nyquist rejection (alternating +-1000 -> 0)");

        valid_in <= '0';

        -- ================================================================
        -- Done
        -- ================================================================
        wait for 5 * CLK_PERIOD;
        report "=== Simulation complete ===" severity note;
        sim_done <= true;
        wait;

    end process stim_proc;

end architecture sim;
