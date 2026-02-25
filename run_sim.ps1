param(
    [string]$CONFIG,
    [string]$TOP,
    [string]$MODE   = "run",
    [string]$SEED   = "default"
)

$SimDo = "sim/scripts/run.do"

if (-not $CONFIG) {
    Write-Host "ERROR: CONFIG is required."
    exit
}

if (-not $TOP) {
    Write-Host "ERROR: TOP is required."
    exit
}

if ($MODE -eq "debug") {
    vsim -do "set CONFIG $CONFIG; set TOP $TOP; set MODE debug; set SEED $SEED; do $SimDo"
}
elseif ($MODE -eq "report") {
    vsim -c -do "set CONFIG $CONFIG; set TOP $TOP; set MODE report; set SEED $SEED; do $SimDo"
}
elseif ($MODE -eq "ci") {
    vsim -c -do "set CONFIG $CONFIG; set TOP $TOP; set MODE ci; set SEED $SEED; do $SimDo"
}
else {
    vsim -c -do "set CONFIG $CONFIG; set TOP $TOP; set MODE run; set SEED $SEED; do $SimDo"
}