-- =============================================================================
-- tb_peak_detector.vhd
-- Testbench for peak_detector
--
-- Tests:
--   1. Positive peak: pulse rises to 1000 then falls -> peak_val=1000, peak_pos=2
--   2. Negative peak: pulse falls to -1000 then rises -> peak_val=-1000, peak_pos=2
--   3. No detection: signal stays below threshold -> peak_valid never asserted
--   4. Two consecutive pulses -> two separate peak outputs
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_peak_detector is
end entity tb_peak_detector;

architecture sim of tb_peak_detector is

    constant CLK_PERIOD : time    := 10 ns;
    constant THRESHOLD  : integer := 500;

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal data_in    : signed(15 downto 0) := (others => '0');
    signal valid_in   : std_logic := '0';
    signal peak_val   : signed(15 downto 0);
    signal peak_pos   : unsigned(15 downto 0);
    signal peak_valid : std_logic;

    signal sim_done   : boolean := false;

    -- Check peak output
    procedure check_peak(
        signal   pval  : in signed(15 downto 0);
        signal   ppos  : in unsigned(15 downto 0);
        signal   pvalid: in std_logic;
        constant exp_val : in integer;
        constant exp_pos : in integer;
        constant msg     : in string
    ) is begin
        if pvalid /= '1' then
            report "FAIL  " & msg & "  peak_valid not asserted" severity error;
            return;
        end if;
        if to_integer(pval) = exp_val and to_integer(ppos) = exp_pos then
            report "PASS  " & msg &
                   "  peak_val=" & integer'image(to_integer(pval)) &
                   "  peak_pos=" & integer'image(to_integer(ppos))
                severity note;
        else
            report "FAIL  " & msg &
                   "  got val=" & integer'image(to_integer(pval)) &
                   " pos=" & integer'image(to_integer(ppos)) &
                   "  expected val=" & integer'image(exp_val) &
                   " pos=" & integer'image(exp_pos)
                severity error;
        end if;
    end procedure;

    -- Send one sample and advance one clock
    procedure send(
        signal din  : out signed(15 downto 0);
        signal vin  : out std_logic;
        constant val: in  integer
    ) is begin
        din <= to_signed(val, 16);
        vin <= '1';
        wait until rising_edge(clk);
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

    dut : entity work.peak_detector
        generic map (
            DATA_BITS => 16,
            THRESHOLD => THRESHOLD,
            POS_BITS  => 16
        )
        port map (
            clk        => clk,
            rst        => rst,
            data_in    => data_in,
            valid_in   => valid_in,
            peak_val   => peak_val,
            peak_pos   => peak_pos,
            peak_valid => peak_valid
        );

    stim_proc : process
    begin
        -- Reset
        rst      <= '1';
        valid_in <= '0';
        wait for 5 * CLK_PERIOD;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);

        -- ==================================================================
        -- Test 1: Positive peak pulse
        --
        -- Input:    0   600  800  1000  700   400   0
        -- State:  IDLE  TRK  TRK  TRK   TRK  DONE IDLE
        -- pos_cnt:      0    1    2      3
        -- max_val:      600  800  1000  1000
        -- max_pos:      0    1    2     2
        --
        -- Expected: peak_val=1000, peak_pos=2
        -- ==================================================================
        report "--- Test 1: Positive peak ---" severity note;

        send(data_in, valid_in,    0);   -- IDLE
        send(data_in, valid_in,  600);   -- TRACKING starts, pos=0
        send(data_in, valid_in,  800);   -- new max, pos=1
        send(data_in, valid_in, 1000);   -- new max, pos=2
        send(data_in, valid_in,  700);   -- no new max, pos=3
        send(data_in, valid_in,  400);   -- below threshold -> DONE
        wait for 1 ns;                   -- DONE outputs peak this cycle
        check_peak(peak_val, peak_pos, peak_valid, 1000, 2, "Positive peak");

        valid_in <= '0';
        wait for 3 * CLK_PERIOD;

        -- ==================================================================
        -- Test 2: Negative peak pulse
        --
        -- Input:    0   -600  -800  -1000  -700   -400   0
        -- abs:      0    600   800   1000   700    400
        -- max_val:        -600  -800  -1000  -1000
        -- max_pos:        0     1     2      2
        --
        -- Expected: peak_val=-1000, peak_pos=2
        -- ==================================================================
        report "--- Test 2: Negative peak ---" severity note;

        send(data_in, valid_in,     0);
        send(data_in, valid_in,  -600);
        send(data_in, valid_in,  -800);
        send(data_in, valid_in, -1000);
        send(data_in, valid_in,  -700);
        send(data_in, valid_in,  -400);
        wait for 1 ns;
        check_peak(peak_val, peak_pos, peak_valid, -1000, 2, "Negative peak");

        valid_in <= '0';
        wait for 3 * CLK_PERIOD;

        -- ==================================================================
        -- Test 3: Signal below threshold -> no detection
        -- peak_valid must stay '0' throughout
        -- ==================================================================
        report "--- Test 3: Below threshold (no detection) ---" severity note;

        send(data_in, valid_in, 100);
        send(data_in, valid_in, 300);
        send(data_in, valid_in, 490);   -- just below threshold
        send(data_in, valid_in, 300);
        send(data_in, valid_in, 100);
        send(data_in, valid_in,   0);
        wait for 1 ns;
        if peak_valid = '0' then
            report "PASS  Below threshold: peak_valid = 0" severity note;
        else
            report "FAIL  Below threshold: peak_valid unexpectedly asserted" severity error;
        end if;

        valid_in <= '0';
        wait for 3 * CLK_PERIOD;

        -- ==================================================================
        -- Test 4: Two consecutive pulses -> two separate detections
        --
        -- Pulse A: 0  600  1000  600  0   -> peak_val=1000, peak_pos=1
        -- Pulse B: 0  700   900  700  0   -> peak_val=900,  peak_pos=1
        -- ==================================================================
        report "--- Test 4: Two consecutive pulses ---" severity note;

        -- Pulse A
        send(data_in, valid_in,    0);
        send(data_in, valid_in,  600);   -- TRACKING, pos=0
        send(data_in, valid_in, 1000);   -- new max, pos=1
        send(data_in, valid_in,  600);   -- pos=2
        send(data_in, valid_in,    0);   -- below threshold -> DONE
        wait for 1 ns;
        check_peak(peak_val, peak_pos, peak_valid, 1000, 1, "Pulse A");

        -- Pulse B (starts immediately after; DUT is back in IDLE)
        send(data_in, valid_in,    0);
        send(data_in, valid_in,  700);   -- TRACKING, pos=0
        send(data_in, valid_in,  900);   -- new max, pos=1
        send(data_in, valid_in,  700);   -- pos=2
        send(data_in, valid_in,    0);   -- DONE
        wait for 1 ns;
        check_peak(peak_val, peak_pos, peak_valid, 900, 1, "Pulse B");

        valid_in <= '0';

        -- ==================================================================
        -- Done
        -- ==================================================================
        wait for 5 * CLK_PERIOD;
        report "=== Peak detector simulation complete ===" severity note;
        sim_done <= true;
        wait;

    end process stim_proc;

end architecture sim;
