$ErrorActionPreference='Stop'
Set-Location -LiteralPath $PSScriptRoot
$bin='D:\gx2026\software\MODELSIM2020\win64'
if(-not (Test-Path work)) { & "$bin\vlib.exe" work }
& "$bin\vlog.exe" -sv 'D:\gx2026\software\quartus13\quartus\eda\sim_lib\altera_mf.v' ../../ip/gray_line_shift.v ../../rtl/image_process/rgb565_to_gray.v ../../rtl/image_process/tft_timing_gen.v ../../rtl/image_process/gray_line_buffer.v ../../rtl/image_process/sobel_filter.v ../../rtl/image_process/video_output_align.v ../../rtl/image_process/sobel_video_pipeline.v tb_sobel_video.sv 2>&1 | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'ModelSim compile failed'}
& "$bin\vsim.exe" -c -l simulation.log work.tb_sobel_video -do run.do
if($LASTEXITCODE -ne 0){throw 'ModelSim simulation failed'}
