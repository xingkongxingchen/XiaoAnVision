set project_root [file normalize [file join [file dirname [info script]] ..]]
cd $project_root
set pin_file [open ./constraints/hx4s20_key_slideshow.adc r]
set pin_text [read $pin_file]
close $pin_file
if {![regexp {set_pin_assignment\s+\{\s*key3\s*\}} $pin_text]} {
    error "K3 physical pin is not verified/assigned; bitstream build is blocked. Do not guess its location."
}
set strategy 1
if {[info exists env(COPY_MAP_STRATEGY)]} {set strategy $env(COPY_MAP_STRATEGY)}
if {![string is integer -strict $strategy] || $strategy < 1 || $strategy > 5} {error "Invalid mapping strategy"}
set map_mode auto
if {[info exists env(COPY_MAP_MODE)]} {set map_mode $env(COPY_MAP_MODE)}
if {$map_mode ni {area_prior logic_level_prior balance_explore auto}} {error "Invalid mapping mode"}
set pack_effort high
if {[info exists env(COPY_PACK_EFFORT)]} {set pack_effort $env(COPY_PACK_EFFORT)}
if {$pack_effort ni {medium high low}} {error "Invalid packing effort"}
if {![regexp {uart_rx\s*\}\s*\{\s*LOCATION\s*=\s*D14;} $pin_text] ||
    ![regexp {uart_tx\s*\}\s*\{\s*LOCATION\s*=\s*G11;} $pin_text]} {
    error "Dedicated panel GPIO UART pins must be D14/G11."
}
set build_dir [file join $project_root build campus_copy_map$strategy]
if {$map_mode ne "area_prior"} {append build_dir _$map_mode}
if {[info exists env(COPY_BUILD_TAG)]} {
    if {![regexp {^[a-z0-9]+$} $env(COPY_BUILD_TAG)]} {error "Invalid build tag"}
    append build_dir _$env(COPY_BUILD_TAG)
}
if {[file exists $build_dir]} {
    error "Preserved candidate exists; use a separate output directory for another build."
}
file mkdir $build_dir

# S4 source list plus two music modules; TD documented area-priority mapping.
set source_files {
    ./rtl/video_clip/clip_file_preloader.v
    ./rtl/video_clip/clip_play_control.v
    ./rtl/video_clip/clip_nn_expand.v
    ./rtl/video_clip/clip_voice_player.v
    ./rtl/control/waveform_switch_control.v
    ./rtl/control/period_setting_control.v
    ./rtl/display/period_setting_osd.v
    ./rtl/control/wall_clock.v
    ./rtl/uart/pc_time_uart.v
    ./rtl/control/panel_control_cdc.v
    ./rtl/control/k3_hold_control.v
    ./rtl/display/k3_params_osd.v
    ./rtl/audio/pcm_master_volume.v
    ./rtl/audio/dual_fat32_pcm_source.v
    ./rtl/audio/fat32_loop_stream.v
    ./rtl/display/scene_chinese_font.v
    ./rtl/audio/emergency_audio_mix.v
    ./rtl/control/emergency_scene_control.v
    ./rtl/display/emergency_scene_overlay.v
    ./rtl/control/emergency_control.v
    ./rtl/uart/emergency_response_tx.v
    ./rtl/uart/baud_tick.v
    ./rtl/uart/uart_rx.v
    ./rtl/uart/uart_tx.v
    ./rtl/uart/uart_response_tx.v
    ./rtl/uart/subtitle_command.v
    ./rtl/uart/subtitle_uart.v
    ./rtl/filesystem/bmp_nn_resampler.v
    ./rtl/display/dynamic_subtitle_overlay.v
    ./rtl/display/promax_text_overlay.v
    ./rtl/display/timestamp_osd.v
    ./rtl/control/thumbnail_controller.v
    ./rtl/control/picture_adjust_control.v
    ./rtl/display/brightness_contrast_adjust.v
    ./rtl/display/picture_params_osd.v
    ./rtl/display/thumbnail_layout.v
    ./rtl/display/promax_audio_waveform.v
    ./rtl/audio/wav_stream_player.v
    ./rtl/audio/fat32_pcm_source.v
    ./rtl/audio/audio_source_mux.v
    ./rtl/audio/sync_fade_gain.v
    ./rtl/top.v
    ./rtl/framebank/four_bank_preload.v
    ./rtl/framebank/pixel_crc_probe.v
    ./rtl/framebank/media_frame_loader.v
    ./rtl/framebank/media_sdram_write_cdc.v
    ./rtl/framebank/media_frame_reader.v
    ./rtl/framebank/media_player_control.v
    ./rtl/framebank/media_video_pipeline.v
    ./rtl/framebank/video_timing_ctrl.v
    ./rtl/framebank/rgb_video_adapter.v
    ./rtl/framebank/fifo_prefetch_2.v
    ./rtl/framebank/video_fade_transition.v
    ./rtl/framebank/afifo_32_16_256.v
    ./rtl/control/dual_key_long_hold_guard.v
    ./rtl/control/dual_key_chord_router.v
    ./rtl/control/slideshow_key_router.v
    ./rtl/control/slideshow_policy.v
    ./rtl/control/reset_sync.v
    ./rtl/control/sync_2ff.v
    ./rtl/control/startup_reset.v
    ./rtl/display/seg7_status_panel.v
    ./rtl/display/load_progress_probe.v
    ./rtl/display/osd_overlay_24.v
    ./rtl/display/status_osd_overlay.v
    ./rtl/base/hdmi_phy_warpper.v
    ./rtl/base/lane_lvds_10_1.v
    ./rtl/base/ip/afifo_16_32_256.v
    ./rtl/base/ip/sys_pll.v
    ./rtl/base/ip/video_pll.v
    ./rtl/base/include/sdr_as_ram.enc.v
    ./rtl/base/include/sdr_init_ref.enc.v
    ./rtl/base/include/sdr_wrrd.enc.v
    ./rtl/filesystem/fat32_volume_scanner.v
    ./rtl/filesystem/fat32_file_streamer.v
    ./rtl/filesystem/sd_sector_adapter.v
    ./rtl/filesystem/fat32_bmp_read.v
    ./rtl/base/sd/color_bar.v
    ./rtl/base/sd/sd_card_cmd.v
    ./rtl/base/sd/sd_card_sec_read_write.v
    ./rtl/base/sd/sd_card_top.v
    ./rtl/base/sd/sdram.v
    ./rtl/base/sd/spi_master.v
    ./rtl/base/sd/video_define.v
    ./rtl/hdmi_audio/hdmi_audio_acr_packetizer.v
    ./rtl/hdmi_audio/hdmi_audio_infoframe_packetizer.v
    ./rtl/hdmi_audio/hdmi_audio_packet_scheduler.v
    ./rtl/hdmi_audio/hdmi_audio_sample_packetizer.v
    ./rtl/hdmi_audio/hdmi_audio_symbol_core.v
    ./rtl/hdmi_audio/hdmi_bch8.v
    ./rtl/hdmi_audio/hdmi_data_island_mapper.v
    ./rtl/hdmi_audio/hdmi_data_island_scheduler.v
    ./rtl/hdmi_audio/hdmi_terc4_encoder.v
    ./rtl/hdmi_audio/hdmi_tmds_channel_encoder.v
    ./rtl/audio/m06_pcm_contract_adapter.v
    ./rtl/integration/media_hdmi_audio_bridge.v
    ./rtl/audio/pcm_media_tone.v
    ./rtl/integration/hdmi_video_position.v
    ./rtl/integration/media_status_cdc.v
}

import_device eagle_s20.db -package EG4S20BG256
set_param flow qor_monitor on

read_hdl -file $source_files -top top
read_adc ./constraints/hx4s20_key_slideshow.adc
optimize_rtl
read_sdc ./constraints/hx4s20_key_slideshow.sdc
set_param gate add_map_lut_struct high
set_param gate map_mode $map_mode
set_param gate map_strategy $strategy
set_param gate pack_effort $pack_effort
optimize_gate
legalize_phy_inst
read_sdc ./constraints/hx4s20_key_slideshow.sdc
export_db $build_dir/key_slideshow_gate.db
# Re-place without relaxing any functional clock or timing constraint.
set place_seed 29
if {[info exists env(COPY_PLACE_SEED)]} {set place_seed $env(COPY_PLACE_SEED)}
if {$place_seed ni {29 23 17}} {error "Invalid scoped placement seed"}
set_param place seed $place_seed
set_param place effort high
set_param place hfn_opt_effort high
set_param place opt_timing ultra
set_param place logic_level_opt on
set_param place post_place_opt ultra
set_param route fix_hold off
set_param route timing greedy
set_param route effort routability
place
update_timing -mode manhattan
report_timing_summary -file $build_dir/place.timing
route
fix_hold
update_timing -mode final
report_qor -step route -file $build_dir/route.qor
report_area -io_info -file $build_dir/route.area
report_timing_summary -file $build_dir/route.timing
export_db $build_dir/key_slideshow_route.db
set fh [open $build_dir/route.timing r]
set timing [read $fh]
close $fh
if {![regexp {SWNS: ([-0-9.]+)ns, STNS: ([-0-9.]+)ns} $timing -> sw st] ||
    ![regexp {HWNS: ([-0-9.]+)ns, HTNS: ([-0-9.]+)ns} $timing -> hw ht]} {error "Cannot parse routed timing"}
if {$sw < 0 || $hw < 0 || $st != 0 || $ht != 0} {
    puts "CANDIDATE_REJECTED: negative routed timing; no bitstream generated"
    exit 2
}
bitgen -bit $build_dir/campus_copy.bit
exit
