# =============================================================================
# run_UCIe_PHY_wrapper_windows.ps1 - Windows/PowerShell launcher for the
#                                    UCIe_PHY_wrapper test
#
# Runs the UCIe_PHY_wrapper integration testbench on Questa/ModelSim (Windows).
# Linux users: use run_UCIe_PHY_wrapper_linux.sh instead.
#
# Usage:
#   .\run_UCIe_PHY_wrapper_windows.ps1                          # run test (default)
#   .\run_UCIe_PHY_wrapper_windows.ps1 -MODE debug             # GUI/debug mode
#   .\run_UCIe_PHY_wrapper_windows.ps1 -CONFIG <C> -TOP <T>    # any config/tb
#   .\run_UCIe_PHY_wrapper_windows.ps1 -MODE report -REPORT_EXT html
# =============================================================================

param(
    [string]$CONFIG     = "UCIe_PHY_wrapper",
    [string]$TOP        = "UCIe_PHY_wrapper_tb",
    [string]$MODE       = "run",
    [string]$SEED       = "default",
    [string]$REPORT_EXT = "txt"
)

$SimDo = "sim/scripts/run.do"

# ---- Sanity checks ----------------------------------------------------------
if (-not (Test-Path $SimDo)) {
    Write-Host "ERROR: $SimDo not found. Run this script from the project root."
    exit 1
}

if (-not (Test-Path "sim/listfiles/$CONFIG.f")) {
    Write-Host "ERROR: listfile sim/listfiles/$CONFIG.f not found."
    exit 1
}

if (-not (Get-Command vsim -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: 'vsim' (Questa/ModelSim) not found in PATH."
    exit 1
}

Write-Host "--------------------------------------------------"
Write-Host "CONFIG = $CONFIG"
Write-Host "TOP    = $TOP"
Write-Host "MODE   = $MODE"
Write-Host "SEED   = $SEED"
Write-Host "--------------------------------------------------"

# ---- Launch -----------------------------------------------------------------
$DoCmd = "set CONFIG $CONFIG; set TOP $TOP; set SYNTH 1; set MODE $MODE; set SEED $SEED; set REPORT_EXT $REPORT_EXT; do $SimDo"

if ($MODE -eq "debug") {
    # GUI mode
    vsim -do $DoCmd
}
else {
    # Console/batch mode (run, report, ci)
    vsim -c -do $DoCmd
}
