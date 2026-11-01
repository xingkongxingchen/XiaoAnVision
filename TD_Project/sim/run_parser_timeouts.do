transcript on
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_parser_timeouts]} {vlib work_parser_timeouts}
vlog -sv -work work_parser_timeouts {*}[glob ../rtl/filesystem/*.v] reference_fat32_bmp_read.v tb_parser_timeouts.sv
set c 0
if {[info exists env(TIMER_CASE)]} {set c $env(TIMER_CASE)}
if {$c==0} {vsim -c work_parser_timeouts.tb_parser_timeouts} else {vsim -c work_parser_timeouts.tb_parser_timeouts -gLIMIT=1024 -gREINIT=1024}
run -all
quit -code 0 -f
