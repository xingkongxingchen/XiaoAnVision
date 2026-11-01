onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_clip_overlay]} {vlib work_clip_overlay}
vlog -sv -work work_clip_overlay {*}[glob ../rtl/display/*.v] tb_clip_overlay.sv
vsim -c work_clip_overlay.tb_clip_overlay
run -all
quit -code 0 -f
