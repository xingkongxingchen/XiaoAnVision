onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_file_eq]} {vlib work_file_eq}
vlog -sv -work work_file_eq ../rtl/filesystem/fat32_file_streamer.v reference_file_streamer.v tb_file_stream_equivalence.sv
vsim -c work_file_eq.tb_file_stream_equivalence
run -all
quit -code 0 -f
