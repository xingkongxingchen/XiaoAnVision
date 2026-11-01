onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_period_cached]} {vlib work_period_cached}
vlog -sv -work work_period_cached ../rtl/framebank/media_player_control.v reference_player_control.v tb_period_cached.sv
vsim -c work_period_cached.tb_period_cached -gDIRECT=0 -gEMERGENCY=0 -gDEFAULT_PERIOD=5
run -all
quit -code 0 -f
