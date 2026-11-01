onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_legacy_display]} {vlib work_legacy_display}
vlog -sv -work work_legacy_display F:/qiansai_anlu/sim_release/common/al_map_lut.v {*}[glob ../rtl/framebank/*.v] {*}[glob ../rtl/control/*.v] {*}[glob ../rtl/video_clip/*.v] ../rtl/display/thumbnail_layout.v ../rtl/display/brightness_contrast_adjust.v tb_legacy_display.sv
vsim -c work_legacy_display.tb_p43_pipeline -gQUICK=1 -gDIAG=1 -gINJECT=0
run -all
quit -code 0 -f
