onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_picture_key_context]} {vlib work_picture_key_context}
vlog -sv -work work_picture_key_context ../rtl/control/period_setting_control.v ../rtl/control/slideshow_key_router.v ../rtl/control/dual_key_chord_router.v ../rtl/control/dual_key_long_hold_guard.v ../rtl/control/picture_adjust_control.v tb_picture_key_context.sv
vsim -c work_picture_key_context.tb_picture_key_context
run -all
quit -code 0 -f
