# =============================================================================
# mbtrain_class_based.f — Compile file list for class-based MBTRAIN TB
#
# Usage (VCS example):
#   vcs -f mbtrain_class_based.f -full64 -sverilog +v2k -timescale=1ns/1ps \
#       -debug_access+all -l sim.log
#
# Adjust paths to match your project tree.
# =============================================================================

# ── 1. Project packages (must come first) ─────────────────────────────────────
../rtl/pkg/UCIe_pkg.sv
../rtl/pkg/ltsm_state_n_pkg.sv

# ── 2. TB types package ───────────────────────────────────────────────────────
mbtrain_cb_types_pkg.sv

# ── 3. TB interface ───────────────────────────────────────────────────────────
mbtrain_cb_if.sv

# ── 4. TB component package (includes all class files) ───────────────────────
mbtrain_cb_pkg.sv

# ── 5. RTL files (wrapper and all sub-modules) ───────────────────────────────
../rtl/wrapper_MBTRAIN.sv
../rtl/unit_MBTRAIN_ctrl.sv
../rtl/unit_RXDESKEW_local.sv
../rtl/unit_LINKSPEED_local.sv
# ... (add remaining RTL dependencies here)

# ── 6. TB top ─────────────────────────────────────────────────────────────────
wrapper_MBTRAIN_class_based_tb.sv

# ── (optional) Thin wrapper top ───────────────────────────────────────────────
# mbtrain_cb_tb_top.sv
