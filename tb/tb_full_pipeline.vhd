-- =============================================================================
-- tb_full_pipeline.vhd
-- Testbench for full_pipeline
--
-- Exercises the complete chain:
--   data_in -> [FIR] -> [Threshold] -> detected
--                   -> [Matched Filter] -> [Peak Detector] -> peak_val/pos/valid
--
-- Tests:
--   1. Silence: no detection, no peak
--   2. Template signal (amplitude x4 so it survives FIR scaling):
--      FIR shapes the pulse; MF still produces a clear correlation peak above
--      threshold -> peak_valid fires with meaningful peak_val
--   3. Alternating Nyquist noise (+-1000): FIR suppresses steady-state to 0;
--      transient at signal start may briefly exceed threshold (expected), but
--      once the filter reaches steady state the MF output falls to near zero
--   4. Strong DC (1000): threshold detector fires; flat DC through MF does not
--      resemble the template so no sustained peak
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_full_pipeline is
end entity tb_full_pipeline;

architecture sim of tb_full_pipeline is

    constant CLK_PERIOD : time    := 10 ns;
    constant DATA_BITS  : integer := 16;
    constant THRESHOLD  : integer := 190;

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal data_in    : signed(DATA_BITS-1 downto 0) := (others => '0');
    signal valid_in   : std_logic := '0';

    signal fir_out    : signed(DATA_BITS-1 downto 0);
    signal fir_valid  : std_logic;
    signal detected   : std_logic;
    signal peak_val   : signed(DATA_BITS-1 downto 0);
    signal peak_pos   : unsigned(15 downto 0);
    signal peak_valid : std_logic;

    signal sim_done   : boolean := false;

    -- Shared peak counter (incremented by monitor, read by stim)
    signal peak_count : integer := 0;

    -- Send one sample and advance one clock
    procedure send(
        signal din : out signed(DATA_BITS-1 downto 0);
        signal vin : out std_logic;
        constant v : in  integer
    ) is begin
        din <= to_signed(v, DATA_BITS);
        vin <= '1';
        wait until rising_edge(clk);
    end procedure;

    -- Idle for N cycles (valid_in = 0)
    procedure idle(
        signal   vin : out std_logic;
        constant n   : in  integer
    ) is begin
        vin <= '0';
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
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

    dut : entity work.full_pipeline
        generic map (
            DATA_BITS => DATA_BITS,
            FIR_TAPS  => 8,
            FIR_SCALE => 8,
            MF_SCALE  => 8,
            THRESHOLD => THRESHOLD,
            POS_BITS  => 16
        )
        port map (
            clk        => clk,
            rst        => rst,
            data_in    => data_in,
            valid_in   => valid_in,
            fir_out    => fir_out,
            fir_valid  => fir_valid,
            detected   => detected,
            peak_val   => peak_val,
            peak_pos   => peak_pos,
            peak_valid => peak_valid
        );

    -- -----------------------------------------------------------------------
    -- Monitor: log every peak_valid pulse and increment counter
    -- -----------------------------------------------------------------------
    monitor_proc : process
    begin
        wait until rising_edge(clk);
        if peak_valid = '1' then
            peak_count <= peak_count + 1;
            report "PEAK  peak_val=" & integer'image(to_integer(peak_val)) &
                   "  peak_pos=" & integer'image(to_integer(peak_pos))
                severity note;
        end if;
    end process;

    stim_proc : process
        variable prev_count : integer;
    begin
        -- Reset
        rst      <= '1';
        valid_in <= '0';
        wait for 5 * CLK_PERIOD;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);

        -- ==================================================================
        -- Test 1: Silence -> no detection, no peak
        -- ==================================================================
        report "--- Test 1: Silence ---" severity note;
        prev_count := peak_count;

        for i in 0 to 15 loop
            send(data_in, valid_in, 0);
        end loop;
        idle(valid_in, 5);
        wait for 1 ns;

        if detected = '0' and peak_count = prev_count then
            report "PASS  Silence: detected=0, no peaks" severity note;
        else
            report "FAIL  Silence: detected=" & std_logic'image(detected) &
                   "  peaks=" & integer'image(peak_count - prev_count)
                severity error;
        end if;

        -- ==================================================================
        -- Test 2: Template x4 through full pipeline -> peak_valid fires
        --
        -- Template T = [0,50,150,250,100,0,0,0] scaled x4 to survive FIR.
        -- The FIR will shape the pulse (low-pass), but the MF still produces
        -- a correlation peak above THRESHOLD=190.
        -- ==================================================================
        report "--- Test 2: Scaled template (expect >= 1 peak) ---"
            severity note;
        prev_count := peak_count;

        send(data_in, valid_in,    0);
        send(data_in, valid_in,  200);
        send(data_in, valid_in,  600);
        send(data_in, valid_in, 1000);
        send(data_in, valid_in,  400);
        send(data_in, valid_in,    0);
        send(data_in, valid_in,    0);
        send(data_in, valid_in,    0);
        -- Flush: FIR(8) + MF(8) + peak settling
        for i in 0 to 19 loop
            send(data_in, valid_in, 0);
        end loop;
        idle(valid_in, 5);
        wait for 1 ns;

        if peak_count > prev_count then
            report "PASS  Template: " &
                   integer'image(peak_count - prev_count) &
                   " peak(s) detected (see PEAK lines above)"
                severity note;
        else
            report "FAIL  Template: no peak detected" severity error;
        end if;

        -- ==================================================================
        -- Test 3: Alternating Nyquist noise (+-1000)
        --
        -- FIR: H(Nyquist) = 0 in steady state (sum of alternating coefficients
        -- = -1+6+25-110+110-25-6+1 = 0).
        --
        -- Two types of transient exist and are NOT checked here:
        --   (a) Startup transient: first 8+8 cycles while FIR and MF fill
        --   (b) Termination transient: when noise ends and zeros flush through
        -- Both are expected physical behaviour at signal edges.
        --
        -- What we DO check: during pure steady-state alternating noise
        -- (no transitions), the MF output stays at 0 and no peaks occur.
        -- Measurement window = cycles 24-39 (well clear of both transients).
        -- ==================================================================
        report "--- Test 3: Alternating Nyquist noise ---" severity note;

        -- Cycles 0-23: warmup (FIR + MF both settle; peaks may appear)
        for k in 0 to 23 loop
            if k mod 2 = 0 then
                send(data_in, valid_in,  1000);
            else
                send(data_in, valid_in, -1000);
            end if;
        end loop;
        wait for 1 ns;
        prev_count := peak_count;   -- snapshot: both FIR and MF fully settled

        -- Cycles 24-39: pure steady state, no transitions -> must be zero peaks
        for k in 0 to 15 loop
            if k mod 2 = 0 then
                send(data_in, valid_in,  1000);
            else
                send(data_in, valid_in, -1000);
            end if;
        end loop;
        wait for 1 ns;

        if peak_count = prev_count then
            report "PASS  Nyquist noise steady-state: no peaks (cycles 24-39)"
                severity note;
        else
            report "FAIL  Nyquist noise: " &
                   integer'image(peak_count - prev_count) &
                   " peak(s) during steady state"
                severity error;
        end if;

        -- Flush (termination transients expected here; not checked)
        for i in 0 to 19 loop
            send(data_in, valid_in, 0);
        end loop;
        idle(valid_in, 5);

        -- ==================================================================
        -- Test 4: Strong DC (1000) -> threshold detector fires
        -- ==================================================================
        report "--- Test 4: Strong DC (threshold fires) ---" severity note;

        for i in 0 to 9 loop
            send(data_in, valid_in, 1000);
        end loop;
        wait for 1 ns;

        if detected = '1' then
            report "PASS  Strong DC: threshold detected=1" severity note;
        else
            report "FAIL  Strong DC: threshold did not fire" severity error;
        end if;

        -- Flush
        for i in 0 to 19 loop
            send(data_in, valid_in, 0);
        end loop;
        idle(valid_in, 5);

        -- ==================================================================
        -- Done
        -- ==================================================================
        wait for 5 * CLK_PERIOD;
        report "=== Full pipeline simulation complete ===" severity note;
        sim_done <= true;
        wait;

    end process stim_proc;

end architecture sim;
