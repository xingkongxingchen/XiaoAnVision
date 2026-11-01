transcript on
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
vlib work_finish_negative
vlog -sv -work work_finish_negative {*}[glob ../rtl/filesystem/*.v] p36_parser_reference.v p37_finish_mutant.v tb_parser_finish_mutant.sv
vsim -c work_finish_negative.tb_parser_finish_mutant -gSCALE=1
run -all
quit -code 0 -f
