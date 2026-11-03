param(
    [string]$VivadoBin = 'C:\Vivado\Vivado\2023.2\bin',
    [string]$WorkDirectory = (Join-Path $env:TEMP 'sdram_2port_equivalence')
)
$ErrorActionPreference = 'Stop'
$verificationDirectory = $PSScriptRoot
$newDirectory = Split-Path $verificationDirectory -Parent
$rtlDirectory = Split-Path $newDirectory -Parent
$oldDirectory = Join-Path $rtlDirectory 'Sdram_Control_4Port'
$workPath = [System.IO.Path]::GetFullPath($WorkDirectory)
# Keep compiler artifacts separate from all RTL sources. No existing files are deleted.
if ($workPath.StartsWith($rtlDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Use a work directory outside the rtl directory.'
}
New-Item -ItemType Directory -Path $workPath -Force | Out-Null
$files = @()
foreach ($directory in @($oldDirectory, $newDirectory)) {
    foreach ($file in Get-ChildItem -LiteralPath $directory -File) {
        if ($file.Extension -in @('.v', '.h')) {
            Copy-Item -LiteralPath $file.FullName -Destination $workPath -Force
            if ($file.Extension -eq '.v') { $files += $file.Name }
        }
    }
}
foreach ($name in @('dcfifo_model.v', 'tb_equivalence.sv')) {
    Copy-Item -LiteralPath (Join-Path $verificationDirectory $name) -Destination $workPath -Force
    $files += $name
}
Push-Location -LiteralPath $workPath
try {
    & (Join-Path $VivadoBin 'xvlog.bat') --sv --work work -i . @files
    if ($LASTEXITCODE -ne 0) { throw 'Verilog compilation failed.' }
    & (Join-Path $VivadoBin 'xelab.bat') work.tb_equivalence -s tb_equivalence_sim --debug typical --timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { throw 'Simulation elaboration failed.' }
    & (Join-Path $VivadoBin 'xsim.bat') tb_equivalence_sim -R
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed.' }
    $simulationLog = Get-Content -LiteralPath (Join-Path $workPath 'xsim.log') -Raw
    if ($simulationLog -notmatch 'PASS: all four old/new controller equivalence cases completed\.') {
        throw 'Simulation did not report successful completion.'
    }
    Write-Output "Verification passed. Logs: $workPath"
} finally {
    Pop-Location
}
