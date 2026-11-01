onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_clip_control_collision]} {vlib work_clip_control_collision}
vlog -sv -work work_clip_control_collision {*}[glob ../rtl/video_clip/*.v] ../rtl/filesystem/fat32_file_streamer.v tb_clip_control.sv
vsim -c work_clip_control_collision.tb_clip_control -gFRAME_PERIOD=1000
run -all
quit -code 0 -f
