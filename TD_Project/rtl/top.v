`timescale 1ns/1ps
// Lecture 8: four resident banks; baseline IP, clock rates and pinout preserved.
module top(
 input wire clk,rst_n,key1,key2,key3,
 input wire uart_rx,emergency_switch,pc_uart_rx,period_switch,waveform_switch,clip_switch,
 output wire uart_tx,pc_uart_tx,
 output wire[7:0]seg_sel,seg_data,
 output wire HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,
 output wire HDMI_DDC_SCL,inout wire HDMI_DDC_SDA,
 output wire sd_ncs,sd_dclk,sd_mosi,input wire sd_miso
);
 wire sd_card_clk,ext_mem_clk,ext_mem_clk_sft,video_clk,hdmi_5x_clk;
 wire sys_pll_locked,video_pll_locked,pll_reset;
 wire ctrl_rst_n,sd_rst_n,mem_rst_n,pixel_rst_n,loader_rst_n;
 wire Sdr_init_done,Sdr_init_ref_vld,Sdr_busy;
 wire App_wr_en,App_rd_en,Sdr_rd_en;
 wire[20:0]App_wr_addr,App_rd_addr;
 wire[31:0]App_wr_din,Sdr_rd_dout;
 wire[3:0]App_wr_dm;
 startup_reset u_startup_reset(
  .ref_clk(clk),.sd_clk(sd_card_clk),.mem_clk(ext_mem_clk),.pixel_clk(video_clk),
  .key_rst_n(rst_n),.sys_locked(sys_pll_locked),.video_locked(video_pll_locked),
  .mem_init_done(Sdr_init_done),.pll_reset(pll_reset),.ctrl_rst_n(ctrl_rst_n),
  .sd_rst_n(sd_rst_n),.mem_rst_n(mem_rst_n),.pixel_rst_n(pixel_rst_n),.loader_rst_n(loader_rst_n));
 sys_pll sys_pll_m0(.refclk(clk),.clk0_out(sd_card_clk),.clk1_out(ext_mem_clk),
  .clk2_out(ext_mem_clk_sft),.locked(sys_pll_locked),.reset(pll_reset));
 video_pll video_pll_m0(.refclk(clk),.clk0_out(video_clk),.clk1_out(hdmi_5x_clk),
  .locked(video_pll_locked),.reset(pll_reset));
 wire[3:0]complete,load_state;
 reg ready;wire pictures_ready,clip_init_done,clip_ready,clip_active,clip_restart;
 wire clip_write_en,clip_write_reset,clip_write_full,clip_write_idle;
 wire[20:0]clip_write_addr;wire[31:0]clip_write_data;wire[7:0]clip_error;
 wire clip_voice_write_en;wire[13:0]clip_voice_write_addr;wire[7:0]clip_voice_write_data;
 // Both preload completion flags are sticky until reset. Register their
 // handoff once, rather than extending the new boot path into every key CE.
 always @(posedge sd_card_clk or negedge loader_rst_n)begin
  if(!loader_rst_n)ready<=0;
  else if(pictures_ready && clip_init_done)ready<=1;
 end
 wire[2:0]found;
 wire[1:0]load_index,active_index;
 wire[7:0]load_error,video_error;
 wire[31:0]file_len,pixel_offset;
 wire[31:0]timeout_trace,timeout_lba;
 wire[31:0]boot_trace,boot_command;
 wire audio_sd_req,audio_sd_ready,audio_sd_valid,audio_sd_end;
 wire[31:0]audio_sd_lba;wire[7:0]audio_sd_byte;
 wire[3:0]src_checked,pix_checked;
 wire src_fault,pix_fault,src_protocol_fault;
 wire[1:0]src_diag_index,pix_diag_index;
 wire[31:0]src_actual,src_expected,pix_actual,pix_expected;
 four_bank_preload #(.ENABLE_AUDIO(1),.ENABLE_SCALE(1),.ENABLE_CRC_DIAG(1),.ENABLE_CLIP(1)) u_preload(
  .diag_checked(src_checked),.diag_fault(src_fault),.diag_protocol_fault(src_protocol_fault),
  .diag_index(src_diag_index),.diag_actual(src_actual),.diag_expected(src_expected),
  .clk(sd_card_clk),.rst_n(loader_rst_n),.mem_clk(ext_mem_clk),.mem_rst_n(mem_rst_n),
  .controller_busy(Sdr_busy),.sd_ncs(sd_ncs),.sd_dclk(sd_dclk),.sd_mosi(sd_mosi),.sd_miso(sd_miso),
  .app_wr_en(App_wr_en),.app_wr_addr(App_wr_addr),.app_wr_data(App_wr_din),.app_wr_mask(App_wr_dm),
  .complete(complete),.ready(pictures_ready),.found(found),.load_index(load_index),.state(load_state),
  .error(load_error),.file_len(file_len),.pixel_offset(pixel_offset),
  .timeout_trace(timeout_trace),.timeout_lba(timeout_lba),
  .boot_trace(boot_trace),.boot_command(boot_command),
  .audio_sd_req(audio_sd_req),.audio_sd_lba(audio_sd_lba),.audio_sd_ready(audio_sd_ready),
  .audio_sd_valid(audio_sd_valid),.audio_sd_end(audio_sd_end),.audio_sd_byte(audio_sd_byte),
  .clip_write_en(clip_write_en),.clip_write_reset(clip_write_reset),.clip_write_addr(clip_write_addr),
  .clip_write_data(clip_write_data),.clip_write_full(clip_write_full),.clip_write_idle(clip_write_idle));
 wire next_event,prev_event,auto_toggle_event,auto_enabled;
 wire thumbnail_toggle_event;
 wire picture_menu_event,picture_menu,picture_menu_pix;
 wire[7:0]picture_brightness,picture_contrast;
 wire[7:0]master_volume;
 wire[1:0]param_selected;
 wire k3_select,k3_step;
 wire scene_block_controls;
 wire period_setting,normal_keys_enabled,period_valid;
 wire[31:0]period_cycles;
 wire[5:0]period_seconds;
 wire[7:0]period_bcd;
 period_setting_control u_period_control(.clk(sd_card_clk),.rst_n(loader_rst_n),
  .enable(ready),.emergency(scene_block_controls),.switch_in(period_switch),
  .key_plus_n(key1),.key_minus_n(key2),.setting_mode(period_setting),
  .normal_keys_enabled(normal_keys_enabled),.period_valid(period_valid),
  .period_cycles(period_cycles),.period_seconds(period_seconds),.period_bcd(period_bcd));
 // PICTURE_KEY_STAGE_BEGIN
 // Only the eligibility condition is registered. The key router is reset
 // whenever normal_keys_enabled is low; its debounced release events cannot
 // occur until this condition has already settled. No command pulse is delayed.
 reg picture_key_context;
 always @(posedge sd_card_clk or negedge loader_rst_n)begin
  if(!loader_rst_n)picture_key_context<=0;
  else picture_key_context<=normal_keys_enabled;
 end
 // PICTURE_KEY_STAGE_END
 wire panel_valid,panel_done,panel_ok,panel_next,panel_prev,panel_auto_valid,panel_auto_value,panel_param_valid;
 wire[2:0]panel_op;
 wire[7:0]panel_value,panel_param_value;
 wire[1:0]panel_param_id;
 wire video_controls_busy,panel_busy_pix;
 wire panel_busy_ctrl=video_controls_busy || picture_menu || scene_block_controls || !ready;
 panel_control_cdc u_panel_control(
  .pix_clk(video_clk),.pix_rst_n(pixel_rst_n),.request_valid(panel_valid),.request_op(panel_op),.request_value(panel_value),
  .response_done(panel_done),.response_ok(panel_ok),.ctrl_clk(sd_card_clk),.ctrl_rst_n(loader_rst_n),
  .enable(ready),.emergency(scene_block_controls),.controls_busy(video_controls_busy || picture_menu),
  .next_event(panel_next),.prev_event(panel_prev),.auto_valid(panel_auto_valid),.auto_value(panel_auto_value),
  .param_valid(panel_param_valid),.param_id(panel_param_id),.param_value(panel_param_value));
 sync_2ff u_panel_busy_pix(.clk(video_clk),.rst_n(pixel_rst_n),.async_in(panel_busy_ctrl),.sync_out(panel_busy_pix));
 slideshow_key_router #(.ENABLE_THUMBNAILS(1),.ENABLE_PICTURE_MENU(1)) u_keys(.clk(sd_card_clk),.rst_n(loader_rst_n && normal_keys_enabled),.key_next_n(key1),
  .key_mode_n(key2),.next_event(next_event),.prev_event(prev_event),.auto_toggle_event(auto_toggle_event),
  .thumbnail_toggle_event(thumbnail_toggle_event),.picture_menu_event(picture_menu_event));
 wire hs,vs,de,lookahead;
 wire[23:0]rgb;
 wire[9:0]video_x;
 wire[7:0]fade_alpha,fade_gain;
 wire fade_active,frame_start;
 wire emergency_scene_active,emergency_missing;
 wire emergency_active;
 wire[1:0]emergency_source;
 k3_hold_control u_k3(.clk(sd_card_clk),.rst_n(loader_rst_n),.key_n(key3),
  .enable(ready),.emergency(scene_block_controls),.select_event(k3_select),.step_event(k3_step));
 picture_adjust_control #(.ENABLE_EMERGENCY(1),.ENABLE_K3(1),.ENABLE_REMOTE(1)) u_picture_control(.ctrl_clk(sd_card_clk),.ctrl_rst_n(loader_rst_n),
  .remote_valid(panel_param_valid),.remote_id(panel_param_id),.remote_value(panel_param_value),
  .k3_select(k3_select),.k3_step(k3_step),.volume_pix(master_volume),.selected_pix(param_selected),
  .cancel(scene_block_controls),
  .enable(ready),.short1(next_event && picture_key_context),.short2(auto_toggle_event && picture_key_context),
  .long1((picture_menu_event && normal_keys_enabled) || (period_setting && picture_menu)),
  .menu_mode(picture_menu),.pix_clk(video_clk),.pix_rst_n(pixel_rst_n),.frame_start(frame_start),
  .brightness_pix(picture_brightness),.contrast_pix(picture_contrast),.menu_pix(picture_menu_pix));
 reg fade_frame_q;
 always @(posedge video_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)fade_frame_q<=0;else fade_frame_q<=frame_start;
 end
 sync_fade_gain u_gain(.pix_clk(video_clk),.pix_rst_n(pixel_rst_n),
  .frame_start(fade_frame_q),.alpha_pix(fade_alpha),.fade_active(fade_active),
  .aud_clk(video_clk),.aud_rst_n(pixel_rst_n),.gain_aud(fade_gain));
 media_video_pipeline #(.DEFAULT_PERIOD_CYCLES(300000000),.FADE_FRAMES(16),.ENABLE_THUMBNAILS(1),.ENABLE_PICTURE_ADJUST(1),.ENABLE_THUMBNAIL_SELECT(1),.ENABLE_EMERGENCY(1),.ENABLE_CRC_DIAG(1),.ENABLE_CLIP(1)) u_video(
  .diag_checked(pix_checked),.diag_fault(pix_fault),.diag_index(pix_diag_index),
  .diag_actual(pix_actual),.diag_expected(pix_expected),
  .emergency_requested(|emergency_source),.emergency_scene_active(emergency_scene_active),
  .emergency_missing(emergency_missing),.scene_block_controls(scene_block_controls),
  .thumbnail_toggle_event(thumbnail_toggle_event && normal_keys_enabled),.thumbnail_active(),
  .controls_busy(video_controls_busy),
  .ctrl_clk(sd_card_clk),.ctrl_rst_n(loader_rst_n),
  .next_event(((next_event && normal_keys_enabled) || panel_next) && !picture_menu),
  .prev_event(((prev_event && normal_keys_enabled) || panel_prev) && !picture_menu),
  .toggle_auto_event(auto_toggle_event && normal_keys_enabled && !picture_menu),
  .period_cfg_valid(period_valid),.period_cfg_cycles(period_cycles),
  .auto_cfg_valid(panel_auto_valid),.auto_cfg_enabled(panel_auto_value),.image_complete(complete),.player_enable(ready),
  .clip_switch(clip_switch),.clip_ready(clip_ready),.clip_active(clip_active),.clip_restart(clip_restart),
  .mem_clk(ext_mem_clk),.mem_rst_n(mem_rst_n),.controller_init_done(Sdr_init_done),
  .controller_busy(Sdr_busy),.refresh_active(Sdr_init_ref_vld),.app_rd_en(App_rd_en),
  .app_rd_addr(App_rd_addr),.sdram_rd_valid(Sdr_rd_en),.sdram_rd_data(Sdr_rd_dout),
  .brightness(8'hff),.pix_clk(video_clk),.pix_rst_n(pixel_rst_n),.video_clk(),
  .picture_brightness(picture_brightness),.picture_contrast(picture_contrast),
  .video_hs(hs),.video_vs(vs),.video_de(de),.video_de_lookahead(lookahead),
  .video_rgb(rgb),.video_x(video_x),.active_index(active_index),.pending_index(),
  .auto_enabled(auto_enabled),.frame_start(frame_start),.reader_busy(),.reader_underflow(),.video_error(video_error),
  .video_fade_alpha(fade_alpha),.video_fade_active(fade_active));
 // Match the board-accepted P42 application read scheduling.
 defparam u_video.u_reader.MAX_INFLIGHT_BURSTS=1;
 sdram U3(.Clk(ext_mem_clk),.Clk_sft(ext_mem_clk_sft),.Rst(!mem_rst_n),
  .Sdr_init_done(Sdr_init_done),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),
  .App_wr_en(App_wr_en),.App_wr_addr(App_wr_addr),.App_wr_dm(App_wr_dm),.App_wr_din(App_wr_din),
  .App_rd_en(App_rd_en),.App_rd_addr(App_rd_addr),.Sdr_rd_en(Sdr_rd_en),.Sdr_rd_dout(Sdr_rd_dout));
 wire ready_pix;
 sync_2ff u_ready_pix(.clk(video_clk),.rst_n(pixel_rst_n),.async_in(ready),.sync_out(ready_pix));
 wire[9:0]ch0,ch1,ch2;
 wire hdmi_error,tone_error,pcm_error;
 wire wav_valid,wav_ready,wav_tick,wav_active;
 wire signed[15:0]wav_sample;
 wire alert_valid,alert_ready;wire signed[15:0]alert_sample;
 wire[7:0]wav_error;
 reg[7:0]wav_error1,wav_error2;
 always @(posedge video_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin wav_error1<=0;wav_error2<=0;end
  else begin wav_error1<=wav_error;wav_error2<=wav_error1;end
 end
 dual_fat32_pcm_source #(.ENABLE_CLIP(1)) u_wav_source(.clk(sd_card_clk),.rst_n(loader_rst_n),.enable(audio_sd_ready),
  .sd_read(audio_sd_req),.sd_lba(audio_sd_lba),.sd_valid(audio_sd_valid),
  .sd_byte(audio_sd_byte),.sd_end(audio_sd_end),.pix_clk(video_clk),.pix_rst_n(pixel_rst_n),
  .sample_tick(wav_tick),.normal_ready(wav_ready),.normal_valid(wav_valid),.normal_sample(wav_sample),
  .normal_active(wav_active),.alert_ready(alert_ready),.alert_valid(alert_valid),.alert_sample(alert_sample),
  .alert_active(),.error(wav_error),
  .clip_write_full(clip_write_full),.clip_write_idle(clip_write_idle),.clip_write_en(clip_write_en),
  .clip_write_addr(clip_write_addr),.clip_write_data(clip_write_data),.clip_write_reset(clip_write_reset),
  .clip_init_done(clip_init_done),.clip_ready(clip_ready),.clip_error(clip_error),
  .clip_voice_write_en(clip_voice_write_en),.clip_voice_write_addr(clip_voice_write_addr),.clip_voice_write_data(clip_voice_write_data));
 wire clip_voice_valid;wire signed[15:0]clip_voice_sample;
 clip_voice_player u_clip_voice(.clk(video_clk),.rst_n(pixel_rst_n),.active(clip_active),.restart(clip_restart),
  .write_clk(sd_card_clk),.write_en(clip_voice_write_en),.write_addr(clip_voice_write_addr),.write_data(clip_voice_write_data),
  .sample_tick(wav_tick),.sample_ready(wav_ready),.sample_valid(clip_voice_valid),.sample_out(clip_voice_sample));
 wire[7:0]pixel_error;
 reg[7:0]clip_error_pix1,clip_error_pix2;
 always @(posedge video_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin clip_error_pix1<=0;clip_error_pix2<=0;end
  else begin clip_error_pix1<=clip_error;clip_error_pix2<=clip_error_pix1;end
 end
 assign pixel_error=video_error!=0 ? video_error :
                    hdmi_error ? 8'h81 : tone_error ? 8'h82 : pcm_error ? 8'h83 :
                    wav_error2!=0 ? wav_error2 : clip_error_pix2;
 // MiCu lesson 9: overlay the already aligned RGB bundle without latency.
 // The delayed VS edge is after the player commits its new bank index.
 wire[23:0]osd_rgb;
 wire overlay_de=de && !clip_active;
 wire[23:0]waveform_rgb;
 wire[23:0]subtitle_rgb;
 wire pcm_tap_valid;
 wire signed[15:0]pcm_tap_left;
 wire osd_auto_enabled;
 sync_2ff u_osd_auto(.clk(video_clk),.rst_n(pixel_rst_n),
  .async_in(auto_enabled),.sync_out(osd_auto_enabled));
 osd_overlay_24 #(.ENABLE_PICTURE_PARAMS(0)) u_osd_overlay(
  .clk(video_clk),.rst_n(pixel_rst_n),.vsync(vs),.de(overlay_de),.rgb_in(rgb),
  .pixel_x(video_x),.active_index(active_index),.auto_enabled(osd_auto_enabled),
  .picture_brightness(picture_brightness),.picture_contrast(picture_contrast),.picture_menu(picture_menu_pix),
  .error_code(pixel_error),.rgb_out(osd_rgb),.de_out(),.osd_active());
 wire[255:0]uart_text;
 wire[5:0]uart_length;
 wire uart_subtitle_enable,uart_restart;
 wire wall_valid,wall_set;
 wire[23:0]wall_bcd,wall_set_bcd;
 pc_time_uart u_pc_time(.clk(video_clk),.rst_n(pixel_rst_n),.rx(pc_uart_rx),.tx(pc_uart_tx),
  .clock_valid(wall_valid),.clock_bcd(wall_bcd),.set_valid(wall_set),.set_bcd(wall_set_bcd));
 wall_clock u_wall_clock(.clk(video_clk),.rst_n(pixel_rst_n),.set_valid(wall_set),
  .set_bcd(wall_set_bcd),.valid(wall_valid),.bcd(wall_bcd));
 subtitle_uart #(.ENABLE_EMERGENCY_LOCK(1),.ENABLE_PANEL(1)) u_subtitle_uart(.clk(video_clk),.rst_n(pixel_rst_n),.rx(uart_rx),.tx(uart_tx),
  .panel_done(panel_done),.panel_ok(panel_ok),.panel_valid(panel_valid),.panel_op(panel_op),.panel_value(panel_value),
  .picture_index(active_index),.autoplay(osd_auto_enabled),.control_busy(panel_busy_pix),
  .brightness(picture_brightness),.contrast(picture_contrast),.volume(master_volume),
  .scene_takeover(emergency_scene_active),
  .emergency_switch(emergency_switch),.emergency_active(emergency_active),.emergency_source(emergency_source),
  .vsync(vs),.text_bytes(uart_text),.text_length(uart_length),
  .subtitle_enable(uart_subtitle_enable),.restart_toggle(uart_restart));
 dynamic_subtitle_overlay #(.UART_CONTROL(1),.WALL_TIME(1)) u_dynamic_osd(
  .clock_valid(wall_valid),.clock_bcd(wall_bcd),
  .clk(video_clk),.rst_n(pixel_rst_n),.vsync(vs),.de(overlay_de),.enable(ready_pix),
  .pixel_x(video_x),.rgb_in(osd_rgb),.active_index(active_index),.rgb_out(subtitle_rgb),
  .uart_text(uart_text),.uart_length(uart_length),.uart_enable(uart_subtitle_enable),.uart_restart(uart_restart));
 // S2 adds another overlay mux. Cut the existing long subtitle RGB path;
 // delay the complete video contract together, never RGB alone.
 reg out_hs,out_vs,out_de,out_lookahead,out_scene,out_missing,out_ready;
 reg[9:0]out_x;
 reg[23:0]out_rgb;
 always @(posedge video_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin
   out_hs<=1;out_vs<=1;out_de<=0;out_lookahead<=0;out_scene<=0;out_missing<=0;out_ready<=0;out_x<=0;out_rgb<=0;
  end else begin
   out_hs<=hs;out_vs<=vs;out_de<=de;out_lookahead<=lookahead;out_x<=video_x;
   out_scene<=emergency_scene_active;out_missing<=emergency_missing;out_ready<=ready_pix;
   out_rgb<=emergency_scene_active ? rgb : subtitle_rgb;
  end
 end
 wire waveform_visible;
 wire out_overlay_de=out_de && !clip_active;
 waveform_switch_control u_waveform_switch(.clk(video_clk),.rst_n(pixel_rst_n),
  .switch_in(waveform_switch),.vsync(out_vs),.visible(waveform_visible));
 promax_audio_waveform u_waveform(
  .clk(video_clk),.rst_n(pixel_rst_n),.vsync(out_vs),.de(out_de),
  .rgb_in(out_rgb),.pixel_x(out_x),.enable((out_ready || out_scene) && waveform_visible && !clip_active),
  .pcm_tap_valid(pcm_tap_valid),.pcm_tap_left(pcm_tap_left),
  .rgb_out(waveform_rgb),.waveform_active());
 wire[23:0]scene_rgb;
 emergency_scene_overlay u_scene_overlay(.clk(video_clk),.rst_n(pixel_rst_n),.vsync(out_vs),.de(out_de),
  .active(out_scene),.missing(out_missing),.pixel_x(out_x),
  .rgb_in(waveform_rgb),.rgb_out(scene_rgb));
 wire[23:0]params_rgb;
 k3_params_osd u_k3_osd(.clk(video_clk),.rst_n(pixel_rst_n),.vsync(out_vs),.de(out_overlay_de),
  .emergency(out_scene),.legacy_menu(picture_menu_pix),.pixel_x(out_x),.rgb_in(scene_rgb),
  .brightness(picture_brightness),.contrast(picture_contrast),.volume(master_volume),
  .selected(param_selected),.rgb_out(params_rgb));
 wire[23:0]period_rgb;
 period_setting_osd u_period_osd(.ctrl_clk(sd_card_clk),.ctrl_rst_n(loader_rst_n),
  .show_ctrl(period_setting),.bcd_ctrl(period_bcd),.clk(video_clk),.rst_n(pixel_rst_n),
  .vsync(out_vs),.de(out_overlay_de),.emergency(out_scene),.pixel_x(out_x),
  .rgb_in(params_rgb),.rgb_out(period_rgb));
 media_hdmi_audio_bridge #(.ENABLE_WAV(1),.ENABLE_EMERGENCY(1),.DUAL_MUSIC(1),.ENABLE_MASTER_VOLUME(1)) u_media_hdmi_audio(
  .master_volume(master_volume),
  .alert_valid(alert_valid),.alert_ready(alert_ready),.alert_sample(alert_sample),
  .emergency(out_scene),
  .pixel_clk(video_clk),.pixel_rst_n(pixel_rst_n),.video_hsync(out_hs),.video_vsync(out_vs),
  .video_de(out_de),.video_de_lookahead(out_lookahead),.video_x(out_x),
  .video_rgb(period_rgb),
  .media_id(active_index),.volume(ready_pix ? (clip_active ? 8'd255 : 8'd64) : 8'd0),
  .wav_valid(clip_active ? clip_voice_valid : wav_valid),.wav_active(clip_active || wav_active),.wav_sample(clip_active ? clip_voice_sample : wav_sample),.fade_gain(fade_gain),
  .wav_ready(wav_ready),.wav_tick(wav_tick),
  .channel0_symbol(ch0),.channel1_symbol(ch1),.channel2_symbol(ch2),
  .sequence_error(hdmi_error),.tone_overflow(tone_error),.pcm_contract_error(pcm_error),
  .blip_active(),.pcm_tap_valid(pcm_tap_valid),.pcm_tap_left(pcm_tap_left));
 assign HDMI_DDC_SCL=1'b1;
 assign HDMI_DDC_SDA=1'bz;
 hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi2phy_wrapper(
  .I_pixel_clk(video_clk),.I_serial_clk(hdmi_5x_clk),.I_rst(!pixel_rst_n),
  .I_tmds_channel_0(ch0),.I_tmds_channel_1(ch1),.I_tmds_channel_2(ch2),
  .I_tmds_channel_clk(10'b0000011111),.O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),
  .O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
 // Freeze first error for board-readable three-page diagnostics.
 reg[7:0]video_err1,video_err2;
 reg trace_captured;
 reg[31:0]page0,page1,page2;
 reg[2:0]pix_fault_sync;
 always @(posedge sd_card_clk or negedge loader_rst_n)begin
  if(!loader_rst_n)begin video_err1<=0;video_err2<=0;trace_captured<=0;page0<=0;page1<=0;page2<=0;pix_fault_sync<=0;end
  else begin
   pix_fault_sync<={pix_fault_sync[1:0],pix_fault};
   video_err1<=pixel_error;video_err2<=video_err1;
   if(!trace_captured && (load_error!=0 || video_err2!=0))begin
    trace_captured<=1;
    page0<={4'he,(load_error!=0 ? load_error : video_err2),load_state,complete,2'd0,load_index,8'd0};
    page1<=load_error==8'h70 ? boot_trace : load_error==8'h16 ? timeout_trace : file_len;
    page2<=load_error==8'h70 ? boot_command : load_error==8'h16 ? timeout_lba : pixel_offset;
   end else if(!trace_captured && src_protocol_fault)begin
    trace_captured<=1;page0<=32'hc3000000;page1<=0;page2<=0;
   end else if(!trace_captured && (src_fault || pix_fault_sync[2]))begin
    // Sticky first-fault buses have settled before the three-stage flag.
    trace_captured<=1;
    page0<={(src_fault ? 8'hc1 : 8'hc2),4'd0,({2'b0,(src_fault ? src_diag_index : pix_diag_index)}+4'd1),16'd0};
    page1<=src_fault ? src_actual : pix_actual;page2<=src_fault ? src_expected : pix_expected;
   end
  end
 end
 reg[11:0]status1,status2;
 always @(posedge clk or negedge ctrl_rst_n)begin
  if(!ctrl_rst_n)begin status1<=0;status2<=0;end
  else begin status1<={ready,active_index,auto_enabled,load_state,found,!ready};status2<=status1;end
 end
 reg[3:0]src_checked1,src_checked2,pix_checked1,pix_checked2;
 reg[1:0]protocol_sync;
 always @(posedge clk or negedge ctrl_rst_n)begin
  if(!ctrl_rst_n)begin src_checked1<=0;src_checked2<=0;pix_checked1<=0;pix_checked2<=0;protocol_sync<=0;end
  else begin
   src_checked1<=src_checked;src_checked2<=src_checked1;
   pix_checked1<=pix_checked;pix_checked2<=pix_checked1;
   protocol_sync<={protocol_sync[0],src_protocol_fault};
  end
 end
 seg7_status_panel #(.ENABLE_CRC_DIAG(1)) u_panel(.clk(clk),.rst_n(ctrl_rst_n),
  .diag_summary({8'hc0,4'd0,src_checked2,4'd0,pix_checked2,7'd0,protocol_sync[1]}),
  .display_valid(status2[11]),.image_index(status2[10:9]),.auto_play_en(status2[8]),
  .loader_state(status2[7:4]),.image_count(status2[3:1]),.load_busy(status2[0]),
  .trace_captured(trace_captured),.trace_page0(page0),.trace_page1(page1),.trace_page2(page2),
  .seg_sel(seg_sel),.seg_data(seg_data));
endmodule
