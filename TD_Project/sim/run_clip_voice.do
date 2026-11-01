onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_clip_voice]} {vlib work_clip_voice}
vlog -sv -work work_clip_voice {*}[glob ../rtl/video_clip/*.v] ../rtl/filesystem/fat32_file_streamer.v tb_clip_voice.sv
vsim -c work_clip_voice.tb_clip_voice 
run -all
quit -code 0 -f
