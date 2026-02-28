param(
    [string]$CONFIG,
    [string]$TOP,
    [string]$MODE   = "run",
    [string]$SEED   = "default",
    [string]$REPORT_EXT   = "txt"
)

$SimDo = "sim/scripts/run.do"

if (-not $CONFIG) {
    Write-Host "ERROR: CONFIG is required."
    Write-Host "Example: ./run_sim.ps1 -CONFIG unit_rdi_packetizer -TOP RDI_Packetizer_tb"
    exit
}

if (-not $TOP) {
    Write-Host "ERROR: TOP is required."
    Write-Host "Example: ./run_sim.ps1 -CONFIG unit_rdi_packetizer -TOP RDI_Packetizer_tb"
    exit
}

if ($MODE -eq "debug") {
    vsim -do "set CONFIG $CONFIG; set TOP $TOP; set MODE debug; set SEED $SEED; do $SimDo"
}
elseif ($MODE -eq "report") {
    vsim -c -do "set CONFIG $CONFIG; set TOP $TOP; set MODE report; set REPORT_EXT $REPORT_EXT; set SEED $SEED; do $SimDo"
}
elseif ($MODE -eq "ci") {
    vsim -c -do "set CONFIG $CONFIG; set TOP $TOP; set MODE ci; set SEED $SEED; do $SimDo"
}
else {
    vsim -c -do "set CONFIG $CONFIG; set TOP $TOP; set MODE run; set SEED $SEED; do $SimDo"
}