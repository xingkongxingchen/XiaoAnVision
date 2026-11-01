onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_clip_boot]} {vlib work_clip_boot}
vlog -sv -work work_clip_boot {*}[glob ../rtl/video_clip/*.v] {*}[glob ../rtl/filesystem/*.v] ../rtl/framebank/media_sdram_write_cdc.v ../rtl/control/reset_sync.v ../rtl/control/sync_2ff.v ../rtl/audio/dual_fat32_pcm_source.v ../rtl/audio/fat32_loop_stream.v ../rtl/audio/wav_stream_player.v tb_clip_boot.sv
vsim -c work_clip_boot.tb_clip_boot
run -all
quit -code 0 -f
