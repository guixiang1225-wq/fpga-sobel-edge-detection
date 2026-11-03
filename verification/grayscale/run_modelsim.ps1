$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$simBin = 'D:\gx2026\software\MODELSIM2020\win64'
if (-not (Test-Path -LiteralPath 'work')) {
    & (Join-Path $simBin 'vlib.exe') work
    if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
}
& (Join-Path $simBin 'vlog.exe') -sv -work work ../../rtl/image_process/rgb565_to_gray.v tb_rgb565_to_gray.sv
if ($LASTEXITCODE -ne 0) { throw 'vlog failed' }
& (Join-Path $simBin 'vsim.exe') -c -l simulation.log work.tb_rgb565_to_gray -do run.do
if ($LASTEXITCODE -ne 0) { throw 'vsim failed' }
