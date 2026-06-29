#!/usr/bin/env bash
# =============================================================================
# run_UCIe_PHY_wrapper_linux.sh - Linux/Bash launcher for the UCIe_PHY_wrapper test
#
# Runs the UCIe_PHY_wrapper integration testbench on Questa/ModelSim (Linux).
# Windows users: use run_UCIe_PHY_wrapper_windows.ps1 instead.
#
# Usage:
#   ./run_UCIe_PHY_wrapper_linux.sh                      # run UCIe_PHY_wrapper test (default)
#   ./run_UCIe_PHY_wrapper_linux.sh -m debug             # GUI/debug mode
#   ./run_UCIe_PHY_wrapper_linux.sh -c <CONFIG> -t <TOP> # run any other config/testbench
#   ./run_UCIe_PHY_wrapper_linux.sh -m report -e html    # coverage report (html|txt)
#
# Options:
#   -c CONFIG       listfile name under sim/listfiles/<CONFIG>.f
#   -t TOP          top-level testbench module
#   -m MODE         run | debug | report | ci      (default: run)
#   -s SEED         default | random | <number>    (default: default)
#   -e REPORT_EXT   txt | html                      (default: txt)
#   -h              show this help
# =============================================================================

set -euo pipefail

# ---- Defaults: UCIe_PHY_wrapper integration test ----------------------------
CONFIG="UCIe_PHY_wrapper"
TOP="UCIe_PHY_wrapper_tb"
MODE="run"
SEED="default"
REPORT_EXT="txt"

SIM_DO="sim/scripts/run.do"

usage() {
    grep '^#' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts ":c:t:m:s:e:h" opt; do
    case "$opt" in
        c) CONFIG="$OPTARG" ;;
        t) TOP="$OPTARG" ;;
        m) MODE="$OPTARG" ;;
        s) SEED="$OPTARG" ;;
        e) REPORT_EXT="$OPTARG" ;;
        h) usage 0 ;;
        \?) echo "ERROR: unknown option -$OPTARG" >&2; usage 1 ;;
        :)  echo "ERROR: option -$OPTARG requires an argument" >&2; usage 1 ;;
    esac
done

# ---- Sanity checks ----------------------------------------------------------
if [[ ! -f "$SIM_DO" ]]; then
    echo "ERROR: $SIM_DO not found. Run this script from the project root." >&2
    exit 1
fi

if [[ ! -f "sim/listfiles/$CONFIG.f" ]]; then
    echo "ERROR: listfile sim/listfiles/$CONFIG.f not found." >&2
    exit 1
fi

if ! command -v vsim >/dev/null 2>&1; then
    echo "ERROR: 'vsim' (Questa/ModelSim) not found in PATH." >&2
    exit 1
fi

echo "--------------------------------------------------"
echo "CONFIG = $CONFIG"
echo "TOP    = $TOP"
echo "MODE   = $MODE"
echo "SEED   = $SEED"
echo "--------------------------------------------------"

# ---- Launch -----------------------------------------------------------------
DO_CMD="set CONFIG $CONFIG; set TOP $TOP; set SYNTH 1;  set MODE $MODE; set SEED $SEED; set REPORT_EXT $REPORT_EXT; do $SIM_DO"

if [[ "$MODE" == "debug" ]]; then
    # GUI mode
    vsim -do "$DO_CMD"
else
    # Console/batch mode (run, report, ci)
    vsim -c -do "$DO_CMD"
fi
