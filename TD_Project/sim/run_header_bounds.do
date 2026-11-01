transcript on
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_header_bounds]} {vlib work_header_bounds}
vlog -sv -work work_header_bounds {*}[glob ../rtl/filesystem/*.v] p21_parser_reference.v tb_header_bounds.sv
set scale 1
if {[info exists env(HEADER_SCALE)]} {set scale $env(HEADER_SCALE)}
vsim -c work_header_bounds.tb_header_bounds -gSCALE=$scale
run -all
quit -code 0 -f
