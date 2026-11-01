onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_bmp_meta]} {vlib work_bmp_meta}
vlog -sv -work work_bmp_meta {*}[glob ../rtl/filesystem/*.v] reference_bmp_metadata.v tb_bmp_metadata.sv
vsim -c work_bmp_meta.tb_bmp_metadata
run -all
quit -code 0 -f
