Write-Host "Cleaning Questa artifacts..."

Remove-Item -Recurse -Force sim/work -ErrorAction SilentlyContinue
Remove-Item -Force sim/logs -ErrorAction SilentlyContinue
Remove-Item -Force transcript -ErrorAction SilentlyContinue
Remove-Item -Force vsim.wlf -ErrorAction SilentlyContinue
Remove-Item -Force modelsim.ini -ErrorAction SilentlyContinue