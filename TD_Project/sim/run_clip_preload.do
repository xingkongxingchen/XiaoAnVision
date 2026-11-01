onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_clip_preload]} {vlib work_clip_preload}
vlog -sv -work work_clip_preload {*}[glob ../rtl/video_clip/*.v] ../rtl/filesystem/fat32_file_streamer.v tb_clip_preload.sv
vsim -c work_clip_preload.tb_clip_preload 
run -all
quit -code 0 -f
