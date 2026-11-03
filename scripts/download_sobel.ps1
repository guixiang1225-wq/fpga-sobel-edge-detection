$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$sof=Join-Path $project 'output_files\ov5640_sdram_hdmi_tft.sof'
$expected=(Get-Content -Raw -LiteralPath (Join-Path $project 'output_files\sobel_build_sha256.txt')).Trim()
if((Get-FileHash -LiteralPath $sof).Hash -ne $expected){throw 'SOF hash mismatch; recompile using scripts/compile.ps1'}
$bin='D:\gx2026\software\quartus13\quartus\bin64'
$chain=& "$bin\jtagconfig.exe" 2>&1
if($LASTEXITCODE -ne 0){throw ($chain -join [Environment]::NewLine)}
$text=$chain -join [Environment]::NewLine
if(([regex]::Matches($text,'(?m)^\d+\)')).Count -ne 1 -or
   ([regex]::Matches($text,'(?m)^\s+[0-9A-Fa-f]{8}\s')).Count -ne 1 -or
   $text -notmatch '020F10DD' -or $text -notmatch 'USB-Blaster \[USB-0\]'){
 throw 'Unexpected JTAG chain; inspect cable and target manually'
}
$log=Join-Path $project ('verification\sobel\download_'+(Get-Date -Format yyyyMMdd_HHmmss)+'.log')
& "$bin\quartus_pgm.exe" -c 'USB-Blaster [USB-0]' -m JTAG -o ("p;"+$sof.Replace('\','/')+'@1') 2>&1 | Tee-Object -FilePath $log
if($LASTEXITCODE -ne 0){throw 'FPGA configuration failed'}
