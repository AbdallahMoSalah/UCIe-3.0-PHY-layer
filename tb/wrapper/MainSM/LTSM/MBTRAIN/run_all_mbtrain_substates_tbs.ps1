# run_all_tbs.ps1 - Run all MBTRAIN substate wrapper testbenches
# Run from the UCIe-3.0-PHY-layer directory

$scriptDir = $PSScriptRoot
$simDir = "$scriptDir\..\..\..\..\..\..\UCIe-3.0-PHY-layer"

$tbs = @(
    "wrapper_VALVREF",
    "wrapper_DATAVREF",
    "wrapper_SPEEDIDLE",
    "wrapper_TXSELFCAL",
    "wrapper_RXCLKCAL",
    "wrapper_VALTRAINCENTER",
    "wrapper_VALTRAINVREF",
    "wrapper_DATATRAINCENTER1",
    "wrapper_DATATRAINVREF",
    "wrapper_RXDESKEW",
    "wrapper_DATATRAINCENTER2",
    "wrapper_LINKSPEED",
    "wrapper_REPAIR",
    "wrapper_MBTRAIN"
)

$listfileBase = "./sim/listfiles"
$passed = @()
$failed = @()

foreach ($tb in $tbs) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Running: $tb" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # Copy listfile to intermediate
    $listfile = "$simDir\sim\listfiles\$tb.f"
    $intermediate = "$simDir\sim\listfiles\intermediate_listfile.f"
    Copy-Item -Path $listfile -Destination $intermediate -Force

    # Run simulation
    $result = & "$simDir\run_sim.ps1" -CONFIG intermediate_listfile -TOP "${tb}_tb" -MODE run 2>&1
    $output = $result -join "`n"

    if ($output -match "MBTRAIN_TB_RESULT: SUCCESS") {
        Write-Host "PASSED: $tb" -ForegroundColor Green
        $passed += $tb
    }
    elseif ($output -match "MBTRAIN_TB_RESULT: FAILURE" -or ($output -match "Error|ERROR|error" -and $output -notmatch "0 Errors")) {
        Write-Host "FAILED: $tb" -ForegroundColor Red
        Write-Host "--- Last 30 lines of output ---"
        $lines = $output -split "`n"
        $lines | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }
        $failed += $tb
    }
    else {
        Write-Host "UNKNOWN: $tb - check output" -ForegroundColor Yellow
        $lines = $output -split "`n"
        $lines | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
        $failed += $tb
    }
}

Write-Host "`n========================================"
Write-Host "SUMMARY"
Write-Host "========================================"
Write-Host "PASSED ($($passed.Count)): $($passed -join ', ')" -ForegroundColor Green
Write-Host "FAILED ($($failed.Count)): $($failed -join ', ')" -ForegroundColor Red
