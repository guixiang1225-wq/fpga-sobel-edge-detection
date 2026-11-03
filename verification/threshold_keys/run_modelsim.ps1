$ErrorActionPreference='Stop'
Set-Location -LiteralPath $PSScriptRoot
$bin='D:\gx2026\software\MODELSIM2020\win64'
if(-not (Test-Path work)){& "$bin\vlib.exe" work}
& "$bin\vlog.exe" -sv ../../rtl/image_process/button_press_pulse.v ../../rtl/image_process/sobel_threshold_keys.v ../../rtl/image_process/sobel_filter.v tb_threshold_keys.sv 2>&1 | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'Key compile failed'}
& "$bin\vsim.exe" -c -l simulation.log work.tb_threshold_keys -do run.do
if($LASTEXITCODE -ne 0){throw 'Key simulation failed'}
