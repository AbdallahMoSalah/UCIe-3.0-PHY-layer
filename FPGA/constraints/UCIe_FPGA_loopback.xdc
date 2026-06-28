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
set_false_path -to [get_pins -hier -filter {NAME =~ */u_clk_det/*_w_reg/D}]
set_property ASYNC_REG TRUE [get_cells -hier -filter {NAME =~ */u_clk_det/*_w_reg}]
# -----------------------------------------------------------------------------
# 1. Clock definitions  (one create_clock per PRIMARY clock input port)
#
#    NOTE: with `define FPGA set, gated_lclk is NOT a primary input. It is
#    generated on-chip by the BUFGCE inside unit_clk_gate (lclk gated by the
#    core's o_mb_lclk_g). Vivado propagates lclk through the BUFGCE, so the
#    gated clock stays in the lclk domain and needs NO create_clock here.
#    (The gated_lclk top-level input port is left unused in the FPGA build.)
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# 2. Clock groups  (CDC: which clocks are unrelated)
#
#    The BUFGCE-gated word clock is propagated from lclk, so it stays in the
#    lclk group automatically (no need to list it).
#    pll_clk and clk_sb come from independent sources -> asynchronous.
#    All cross-domain traffic in the design is handled by FIFOs / handshakes,
#    so we tell the tool not to time across these groups.
# -----------------------------------------------------------------------------
