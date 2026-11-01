transcript on
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
vlib work_parser_finish
vlog -sv -work work_parser_finish {*}[glob ../rtl/filesystem/*.v] p36_parser_reference.v tb_parser_finish.sv
set scale 1
if {[info exists env(FINISH_SCALE)]} {set scale $env(FINISH_SCALE)}
vsim -c work_parser_finish.tb_parser_finish -gSCALE=$scale
run -all
quit -code 0 -f
