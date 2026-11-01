onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_clip_pipeline]} {vlib work_clip_pipeline}
vlog -sv -work work_clip_pipeline F:/qiansai_anlu/sim_release/common/al_map_lut.v {*}[glob ../rtl/framebank/*.v] {*}[glob ../rtl/control/*.v] {*}[glob ../rtl/video_clip/*.v] ../rtl/display/thumbnail_layout.v ../rtl/display/brightness_contrast_adjust.v tb_clip_pipeline.sv
vsim -c work_clip_pipeline.tb_clip_pipeline
run -all
quit -code 0 -f
