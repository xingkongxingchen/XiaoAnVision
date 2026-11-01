onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_voice_restart]} {vlib work_voice_restart}
vlog -sv -work work_voice_restart ../rtl/video_clip/clip_voice_player.v tb_clip_voice_restart.sv
vsim -c work_voice_restart.tb_clip_voice_restart
run -all
quit -code 0 -f
