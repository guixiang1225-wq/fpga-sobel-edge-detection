$ErrorActionPreference='Stop'
Set-Location -LiteralPath $PSScriptRoot
$bin='D:\gx2026\software\MODELSIM2020\win64'
if(-not (Test-Path work)) { & "$bin\vlib.exe" work }
& "$bin\vlog.exe" -sv 'D:\gx2026\software\quartus13\quartus\eda\sim_lib\altera_mf.v' ../../rtl/Sdram_Control_4Port/Sdram_RD_FIFO.v ../../ip/gray_line_shift.v ../../rtl/image_process/rgb565_to_gray.v ../../rtl/image_process/tft_timing_gen.v ../../rtl/image_process/gray_line_buffer.v ../../rtl/image_process/sobel_filter.v ../../rtl/image_process/video_output_align.v ../../rtl/image_process/button_press_pulse.v ../../rtl/image_process/sobel_threshold_keys.v ../../rtl/image_process/sobel_video_pipeline.v sobel_video_pipeline_before.v tb_startup.sv 2>&1 | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'Startup ModelSim compile failed'}
& "$bin\vsim.exe" -c -l simulation.log work.tb_startup -do run.do
if($LASTEXITCODE -ne 0){throw 'Startup ModelSim simulation failed'}
if(-not (Select-String -LiteralPath simulation.log -SimpleMatch 'PASS: old threshold=0')) {throw 'Startup test did not pass'}
