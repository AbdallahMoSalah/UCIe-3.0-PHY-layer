# =============================================================================
# UCIe_FPGA_loopback.xdc  -  timing constraints for the digital-only loopback
#
# Top : UCIe_FPGA_loopback  (no PLL inside; all clocks arrive as input ports)
#
# Periods below mirror the simulation TB (digital_ucie_loopback_tb):
#     pll_clk     0.5 ns  -> 2000 MHz   (analog mb_pll bit rate model)
#     lclk        8.0 ns  ->  125 MHz   (MainBand word clock = pll/16)
#     gated_lclk  8.0 ns  ->  125 MHz   (clock-gated copy of lclk)
#     clk_sb     10.0 ns  ->  100 MHz   (Sideband parallel clock)
#
# !! pll_clk @ 2 GHz is NOT achievable in FPGA fabric. For real hardware you
#    MUST lower it (and re-scale the clk-pattern gen/detector counters). The
#    2 GHz value is kept here only so the numbers match the TB. <<<<<<<<<<<<<<<<
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Clock definitions  (one create_clock per PRIMARY clock input port)
#
#    NOTE: with `define FPGA set, gated_lclk is NOT a primary input. It is
#    generated on-chip by the BUFGCE inside unit_clk_gate (lclk gated by the
#    core's o_mb_lclk_g). Vivado propagates lclk through the BUFGCE, so the
#    gated clock stays in the lclk domain and needs NO create_clock here.
#    (The gated_lclk top-level input port is left unused in the FPGA build.)
# -----------------------------------------------------------------------------
create_clock -name pll_clk    -period 2.000  [get_ports pll_clk]
create_clock -name lclk       -period 2.000  [get_ports lclk]
create_clock -name clk_sb     -period 10.000 [get_ports clk_sb]

# -----------------------------------------------------------------------------
# 2. Clock groups  (CDC: which clocks are unrelated)
#
#    The BUFGCE-gated word clock is propagated from lclk, so it stays in the
#    lclk group automatically (no need to list it).
#    pll_clk and clk_sb come from independent sources -> asynchronous.
#    All cross-domain traffic in the design is handled by FIFOs / handshakes,
#    so we tell the tool not to time across these groups.
# -----------------------------------------------------------------------------
set_clock_groups -asynchronous \
    -group {lclk} \
    -group {pll_clk} \
    -group {clk_sb}

# -----------------------------------------------------------------------------
# 3. Input delays  (system-synchronous; placeholder budgets - tune per board)
#
#    Each input is constrained against the clock that actually samples it:
#      - MainBand flit data + RDI adapter face   -> lclk
#      - Sideband config face (lp_cfg / *_crd)   -> clk_sb
#    -max sets the setup budget, -min the hold budget. The values below are
#    ~40% / ~5% of the period as a starting point; replace with the real
#    board/source numbers when known.
# -----------------------------------------------------------------------------

# ---- lclk-domain inputs (period 8 ns) ----
set lclk_in_max 3.0
set lclk_in_min 0.4
set lclk_inputs [get_ports {lp_data[*] lp_irdy lp_valid \
                            lp_state_req[*] lp_clk_ack lp_wake_req \
                            lp_stallack lp_linkerror}]
set_input_delay -clock lclk -max $lclk_in_max $lclk_inputs
set_input_delay -clock lclk -min $lclk_in_min $lclk_inputs

# ---- clk_sb-domain inputs (period 10 ns) ----
set sb_in_max 4.0
set sb_in_min 0.5
set sb_inputs [get_ports {lp_cfg[*] lp_cfg_vld lp_cfg_crd}]
set_input_delay -clock clk_sb -max $sb_in_max $sb_inputs
set_input_delay -clock clk_sb -min $sb_in_min $sb_inputs

# -----------------------------------------------------------------------------
# 4. Asynchronous reset (rst_n is not a clock; don't let it be timed)
# -----------------------------------------------------------------------------
set_false_path -from [get_ports rst_n]