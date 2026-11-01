onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_adapter_narrow]} {vlib work_adapter_narrow}
vlog -sv -work work_adapter_narrow ../rtl/filesystem/sd_sector_adapter.v reference_sd_sector_adapter.v tb_adapter_equivalence.sv
vsim -c work_adapter_narrow.tb_adapter_equivalence
run -all
quit -code 0 -f
