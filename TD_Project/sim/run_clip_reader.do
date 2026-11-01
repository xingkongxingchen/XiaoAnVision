onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_clip_reader]} {vlib work_clip_reader}
vlog -sv -work work_clip_reader F:/qiansai_anlu/sim_release/common/al_map_lut.v ../rtl/framebank/afifo_32_16_256.v ../rtl/framebank/fifo_prefetch_2.v ../rtl/framebank/media_frame_reader.v tb_clip_reader.sv
vsim -c work_clip_reader.tb_clip_reader
run -all
quit -code 0 -f
