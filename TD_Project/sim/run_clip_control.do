onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_clip_control]} {vlib work_clip_control}
vlog -sv -work work_clip_control {*}[glob ../rtl/video_clip/*.v] ../rtl/filesystem/fat32_file_streamer.v tb_clip_control.sv
vsim -c work_clip_control.tb_clip_control 
run -all
quit -code 0 -f
