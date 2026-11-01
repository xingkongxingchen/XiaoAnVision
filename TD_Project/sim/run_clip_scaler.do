onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_clip_scaler]} {vlib work_clip_scaler}
vlog -sv -work work_clip_scaler {*}[glob ../rtl/video_clip/*.v] ../rtl/filesystem/fat32_file_streamer.v tb_clip_scaler.sv
vsim -c work_clip_scaler.tb_clip_scaler 
run -all
quit -code 0 -f
