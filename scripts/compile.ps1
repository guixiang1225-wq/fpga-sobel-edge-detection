$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $project
$log=Join-Path $project ('verification\sobel\compile_'+(Get-Date -Format yyyyMMdd_HHmmss)+'.log')
& 'D:\gx2026\software\quartus13\quartus\bin64\quartus_sh.exe' --flow compile ov5640_sdram_hdmi_tft 2>&1 | Tee-Object -FilePath $log
if($LASTEXITCODE -ne 0){throw 'Quartus compile failed'}
$sof=Join-Path $project 'output_files\ov5640_sdram_hdmi_tft.sof'
(Get-FileHash -LiteralPath $sof).Hash | Set-Content -Encoding ascii -LiteralPath (Join-Path $project 'output_files\sobel_build_sha256.txt')
