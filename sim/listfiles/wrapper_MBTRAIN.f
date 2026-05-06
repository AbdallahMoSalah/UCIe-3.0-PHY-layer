// =============================================================================
// Listfile: wrapper_MBTRAIN.f
// Purpose : Compilation list for wrapper_MBTRAIN + wrapper_D2C_PT integration
//           testbench. Includes all 13 sub-state RTL files, the MBTRAIN
//           controller, both D2C PT modules, and the wrapper RTL.
// Run     : .\run_sim.ps1 -CONFIG wrapper_MBTRAIN -TOP wrapper_MBTRAIN_tb -MODE run
// =============================================================================

// --- Packages (order matters: dependencies first) ---
rtl/common/UCIe_pkg.sv
rtl/MainSM/LTSM/common/ltsm_state_n_pkg.sv
rtl/MainSM/common/LTSM_state_pkg.sv
rtl/MainSM/LTSM/common/internal_ltsm_if.sv

// --- MBTRAIN Controller ---
rtl/MainSM/LTSM/unit_MBTRAIN_ctrl/unit_MBTRAIN_ctrl.sv

// --- Sub-state FSMs (13, ordered by MBTRAIN sequencing) ---
rtl/MainSM/LTSM/MBTRAIN/unit_VALVREF.sv
rtl/MainSM/LTSM/MBTRAIN/unit_DATAVREF.sv
rtl/MainSM/LTSM/MBTRAIN/unit_SPEEDIDLE.sv
rtl/MainSM/LTSM/MBTRAIN/unit_TXSELFCAL.sv
rtl/MainSM/LTSM/MBTRAIN/unit_RXCLKCAL.sv
rtl/MainSM/LTSM/MBTRAIN/unit_VALTRAINCENTER.sv
rtl/MainSM/LTSM/MBTRAIN/unit_VALTRAINVREF.sv
rtl/MainSM/LTSM/MBTRAIN/unit_DATATRAINCENTER1.sv
rtl/MainSM/LTSM/MBTRAIN/unit_DATATRAINVREF.sv
rtl/MainSM/LTSM/MBTRAIN/unit_RXDESKEW/unit_phase_interpolator_for_deskew.sv
rtl/MainSM/LTSM/MBTRAIN/unit_RXDESKEW/unit_RXDESKEW.sv
rtl/MainSM/LTSM/MBTRAIN/unit_DATATRAINCENTER2.sv
rtl/MainSM/LTSM/MBTRAIN/unit_LINKSPEED.sv
rtl/MainSM/LTSM/MBTRAIN/unit_REPAIR.sv

// --- Shared D2C Test Modules ---
rtl/MainSM/LTSM/D2C_PT/unit_TX_D2C_PT.sv
rtl/MainSM/LTSM/D2C_PT/unit_RX_D2C_PT.sv
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT.sv

// --- Wrapper RTL (DUT) ---
rtl/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN.sv

// --- Top-level Testbench ---
tb/wrapper/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN_tb.sv
