transcript on
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_scale_preload]} {vlib work_scale_preload}
vlog -O0 -work work_scale_preload F:/qiansai_anlu/sim_release/common/al_map_lut.v
vlog -sv -work work_scale_preload {*}[glob ../rtl/framebank/*.v] {*}[glob ../rtl/filesystem/*.v] {*}[glob ../rtl/control/*.v] scale_card_model.sv tb_scale_preload.sv
set full 0
if {[info exists env(PRELOAD_FULL)]} {set full $env(PRELOAD_FULL)}
set diag 0
if {[info exists env(PRELOAD_DIAG)]} {set diag $env(PRELOAD_DIAG)}
vsim -c work_scale_preload.tb_scale_preload -gFULL=$full -gDIAG=$diag
run -all
quit -code 0 -f
