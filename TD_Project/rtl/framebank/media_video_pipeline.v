`timescale 1ns/1ps

module media_video_pipeline #(
    parameter integer IMAGE_WORDS = 307200,
    parameter integer ENABLE_CRC_DIAG = 0,
    parameter integer FIFO_DEPTH = 512,
    parameter integer FIFO_MARGIN = 16,
    parameter integer H_ACT = 640,
    parameter integer H_FP = 16,
    parameter integer H_SYNC = 96,
    parameter integer H_BP = 48,
    parameter integer V_ACT = 480,
    parameter integer V_FP = 10,
    parameter integer V_SYNC = 2,
    parameter integer V_BP = 33,
    parameter [31:0] DEFAULT_PERIOD_CYCLES = 32'd250000000,
    parameter [31:0] MIN_PERIOD_CYCLES = 32'd50000000,
    parameter [31:0] MAX_PERIOD_CYCLES = 32'd3000000000,
    // Non-zero enables the fade-out/black/fade-in transition on manual
    // switches and a fade-in on automatic slideshow switches. Zero keeps the
    // legacy direct-switch behaviour for the existing regression suites.
    parameter integer FADE_FRAMES = 0,
    parameter integer ENABLE_THUMBNAILS = 0,
    parameter integer ENABLE_PICTURE_ADJUST = 0,
    parameter integer ENABLE_THUMBNAIL_SELECT = 0,
    parameter integer ENABLE_EMERGENCY = 0,
    parameter integer ENABLE_CLIP = 0
) (
    input  wire        ctrl_clk,
    input  wire        ctrl_rst_n,
    input  wire        next_event,
    input  wire        prev_event,
    input  wire        toggle_auto_event,
    input  wire        thumbnail_toggle_event,
    output wire       thumbnail_active,
    output wire       controls_busy,
    input  wire        period_cfg_valid,
    input  wire [31:0] period_cfg_cycles,
    input  wire        auto_cfg_valid,
    input  wire        auto_cfg_enabled,
    input  wire [3:0]  image_complete,
    input  wire        player_enable,
    input wire clip_switch,clip_ready,output wire clip_active,output wire clip_restart,
    input  wire        emergency_requested,
    output wire       emergency_scene_active,emergency_missing,scene_block_controls,

    input  wire        mem_clk,
    input  wire        mem_rst_n,
    input  wire        controller_init_done,
    input  wire        controller_busy,
    input  wire        refresh_active,
    output wire        app_rd_en,
    output wire [20:0] app_rd_addr,
    input  wire        sdram_rd_valid,
    input  wire [31:0] sdram_rd_data,

    input  wire [7:0]  brightness,
    input  wire [7:0]  picture_brightness,
    input  wire [7:0]  picture_contrast,
    input  wire        pix_clk,
    input  wire        pix_rst_n,
    output wire        video_clk,
    output wire        video_hs,
    output wire        video_vs,
    output wire        video_de,
    output wire        video_de_lookahead,
    output wire [23:0] video_rgb,
    output wire [9:0]  video_x,

    output wire [1:0]  active_index,
    output wire [1:0]  pending_index,
    output wire        auto_enabled,
    output wire        frame_start,
    output wire        reader_busy,
    output wire        reader_underflow,
    output wire [7:0]  video_error,
    output wire [7:0]  video_fade_alpha,
    output wire        video_fade_active,
    output wire [3:0]  diag_checked,
    output wire        diag_fault,
    output wire [1:0]  diag_index,
    output wire [31:0] diag_actual,diag_expected
);
    wire raw_hs;
    wire raw_vs;
    wire raw_de;
    wire [11:0] raw_x;
    wire [11:0] raw_y;
    localparam integer H_BLANK = H_FP + H_SYNC + H_BP;
    wire [11:0] active_x = (raw_x >= H_BLANK) ? raw_x - H_BLANK : 12'd0;
    wire [11:0] active_y = (raw_y >= V_FP+V_SYNC+V_BP) ? raw_y-(V_FP+V_SYNC+V_BP) : 12'd0;
    reg thumb_request_ctrl;
    wire thumb_request_pix;
    wire thumb_mode_pix;
    wire [1:0] thumb_focus_pix;
    wire browse_active,select_event,fade_busy;
    wire request_busy;
    wire clip_ctrl;
    sync_2ff u_clip_ctrl(.clk(ctrl_clk),.rst_n(ctrl_rst_n),.async_in(clip_active),.sync_out(clip_ctrl));
    assign controls_busy=request_busy || fade_busy || browse_active || clip_ctrl;
    wire [1:0] select_index;
    wire[1:0]normal_index,restore_index;
    wire restore_select;
    wire[3:0]normal_complete=ENABLE_EMERGENCY ? (image_complete & 4'b0111) : image_complete;
    wire normal_thumb_mode;
    generate if(ENABLE_EMERGENCY)begin:g_scene
        emergency_scene_control u_scene(
            .pix_clk(pix_clk),.pix_rst_n(pix_rst_n),.frame_start(frame_start),
            .requested(emergency_requested),.normal_index(normal_index),.takeover(emergency_scene_active),
            .ctrl_clk(ctrl_clk),.ctrl_rst_n(ctrl_rst_n),.player_busy(request_busy),
            .block_controls(scene_block_controls),.restore_select(restore_select),.restore_index(restore_index));
    end else begin:g_no_scene
        assign emergency_scene_active=0;assign scene_block_controls=0;
        assign restore_select=0;assign restore_index=0;
    end endgenerate
    assign active_index=emergency_scene_active ? 2'd3 : normal_index;
    assign thumb_mode_pix=normal_thumb_mode && !emergency_scene_active;
    reg[1:0]emergency_valid_sync;
    reg emergency_valid_frame;
    always @(posedge pix_clk or negedge pix_rst_n)begin
        if(!pix_rst_n)begin emergency_valid_sync<=0;emergency_valid_frame<=0;end
        else begin
            emergency_valid_sync<={emergency_valid_sync[0],image_complete[3] && player_enable};
            if(frame_start)emergency_valid_frame<=emergency_valid_sync[1];
        end
    end
    generate if(ENABLE_THUMBNAIL_SELECT)begin : g_select
        thumbnail_controller #(.ENABLE_EMERGENCY(ENABLE_EMERGENCY)) u_thumbnail_control(
            .clk(ctrl_clk),.rst_n(ctrl_rst_n),.enable(player_enable),
            .cancel(scene_block_controls),
            .key_right(next_event && !clip_ctrl),.key_left(toggle_auto_event && !clip_ctrl),
            .key_confirm(prev_event && !clip_ctrl),.key_mode(thumbnail_toggle_event && !clip_ctrl),
            .image_complete(normal_complete),.current_index(pending_index),
            .player_busy(request_busy),.fade_busy(fade_busy),
            .browse_active(browse_active),.select_event(select_event),.select_index(select_index),
            .pix_clk(pix_clk),.pix_rst_n(pix_rst_n),.frame_start(frame_start),
            .view_mode(normal_thumb_mode),.focus_index(thumb_focus_pix));
    end else begin : g_legacy_thumb
    reg mode_pix;
    assign normal_thumb_mode=mode_pix;
    assign thumb_focus_pix=active_index;
    assign browse_active=0;
    assign select_event=0;
    assign select_index=0;
    always @(posedge ctrl_clk or negedge ctrl_rst_n) begin
        if (!ctrl_rst_n) thumb_request_ctrl <= 0;
        else if (ENABLE_THUMBNAILS && thumbnail_toggle_event && player_enable)
            thumb_request_ctrl <= ~thumb_request_ctrl;
    end
    sync_2ff u_thumb_mode_sync(.clk(pix_clk), .rst_n(pix_rst_n),
        .async_in(thumb_request_ctrl), .sync_out(thumb_request_pix));
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) mode_pix <= 0;
        else if (frame_start) mode_pix <= thumb_request_pix;
    end
    end endgenerate
    assign thumbnail_active = thumb_mode_pix;
    wire thumb_de, thumb_border;
    generate if (ENABLE_THUMBNAILS) begin : g_thumbnail
        // MiCu's unmodified 2x2 layout. The reader fetches this coordinate
        // sequence in contiguous 128-word bursts, discarding three of four
        // returned pixels instead of making unsupported random read bursts.
        thumbnail_layout #(.DISPLAY_WIDTH(H_ACT), .DISPLAY_HEIGHT(V_ACT),
            .THUMB_WIDTH(H_ACT/4), .THUMB_HEIGHT(V_ACT/4)) u_layout (
            .in_de(raw_de), .pixel_x(active_x), .pixel_y(active_y),
            .focus_index(thumb_focus_pix), .image_complete(normal_complete),
            .thumb_de(thumb_de), .source_index(), .source_x(), .source_y(),
            .focus_border(thumb_border));
    end else begin : g_no_thumbnail
        assign thumb_de = 1'b0;
        assign thumb_border = 1'b0;
    end endgenerate
    reg raw_vs_q;
    reg [9:0] video_x_q;
    wire index_commit;
    wire [7:0] control_error;
    wire [31:0] active_period_cycles;
    wire [23:0] reader_rgb;
    wire reader_pixel_valid;
    wire reader_done;
    wire [1:0] reader_index;
    wire [7:0] reader_error;
    wire player_enable_pix;
    wire player_enable_mem;
    reg display_armed_pix;
    reg lookahead_q;
    sync_2ff u_enable_mem (.clk(mem_clk), .rst_n(mem_rst_n),
        .async_in(player_enable), .sync_out(player_enable_mem));
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin display_armed_pix <= 0; lookahead_q <= 0; end
        else begin
            if (frame_start && (player_enable_pix || (ENABLE_EMERGENCY && emergency_requested))) display_armed_pix <= 1;
            // Announce video during the final ten blanking characters too.
            lookahead_q <= display_armed_pix && (raw_y >= V_FP+V_SYNC+V_BP) &&
                           (raw_x >= H_BLANK-21);
        end
    end
    assign video_de_lookahead = lookahead_q;
    reg [7:0] reader_error_pix1;
    reg [7:0] reader_error_pix2;
    assign emergency_missing=emergency_scene_active && (!emergency_valid_frame || reader_error_pix2!=0);
    reg [7:0] control_error_pix1;
    reg [7:0] control_error_pix2;
    wire clip_valid,clip_consume,clip_ready_pix,clip_block_pix;
    wire[23:0]clip_rgb;
    wire[20:0]clip_frame_base;
    wire[4:0]clip_frame_index;
    sync_2ff u_clip_ready(.clk(pix_clk),.rst_n(pix_rst_n),.async_in(clip_ready),.sync_out(clip_ready_pix));
    sync_2ff u_clip_block(.clk(pix_clk),.rst_n(pix_rst_n),
        .async_in(request_busy || fade_busy || browse_active),.sync_out(clip_block_pix));
    generate if(ENABLE_CLIP)begin:g_clip
        clip_play_control u_clip_control(.clk(pix_clk),.rst_n(pix_rst_n),.switch_in(clip_switch),
            .ready(clip_ready_pix && player_enable_pix),.frame_start(frame_start),
            .blocked(clip_block_pix || normal_thumb_mode),.emergency(emergency_requested || emergency_scene_active),
            .active(clip_active),.restart(clip_restart),.frame_index(clip_frame_index),.frame_base(clip_frame_base));
        wire[11:0]next_active_x=(raw_x+12'd1>=H_BLANK) ? raw_x+12'd1-H_BLANK : 12'd0;
        clip_nn_expand u_expand(.clk(pix_clk),.rst_n(pix_rst_n),.active(clip_active),.de(raw_de),
            .x(active_x),.y(active_y),.next_x(next_active_x),.source_rgb(reader_rgb),.source_valid(reader_pixel_valid),
            .consume(clip_consume),.rgb(clip_rgb),.valid(clip_valid));
    end else begin:g_no_clip
        assign clip_restart=0;assign clip_active=0;assign clip_frame_base=0;assign clip_frame_index=0;
        assign clip_consume=0;assign clip_rgb=0;assign clip_valid=0;
    end endgenerate
    wire image_data_valid=clip_active ? clip_valid : reader_pixel_valid;
    wire[23:0]image_rgb=clip_active ? clip_rgb : reader_rgb;
    wire [23:0] source_rgb =
        (player_enable_pix && image_data_valid && reader_error_pix2 == 0) ?
        image_rgb : 24'h000000;
    wire [23:0] selected_rgb;
    generate if(ENABLE_PICTURE_ADJUST)begin : g_adjust
        wire[23:0]adjusted;
        brightness_contrast_adjust u_adjust(.in_de(raw_de),.rgb_in(source_rgb),
            .brightness(picture_brightness),.contrast(picture_contrast),
            .out_de(),.rgb_out(adjusted));
        // Keep invalid reader data black even at zero contrast.
        assign selected_rgb=(player_enable_pix && image_data_valid && reader_error_pix2==0)
                            ? adjusted : 24'd0;
    end else begin : g_no_adjust
        assign selected_rgb=source_rgb;
    end endgenerate

    sync_2ff u_player_enable_pix (
        .clk(pix_clk), .rst_n(pix_rst_n), .async_in(player_enable),
        .sync_out(player_enable_pix)
    );

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            reader_error_pix1 <= 8'd0;
            reader_error_pix2 <= 8'd0;
            control_error_pix1 <= 8'd0;
            control_error_pix2 <= 8'd0;
        end else begin
            reader_error_pix1 <= reader_error;
            reader_error_pix2 <= reader_error_pix1;
            control_error_pix1 <= control_error;
            control_error_pix2 <= control_error_pix1;
        end
    end

    video_timing_ctrl #(
        .H_ACT(H_ACT), .H_FP(H_FP), .H_SYNC(H_SYNC), .H_BP(H_BP),
        .V_ACT(V_ACT), .V_FP(V_FP), .V_SYNC(V_SYNC), .V_BP(V_BP),
        .ACTIVE_LAST(1)
    ) u_timing (
        .pclk(pix_clk), .rst_n(pix_rst_n), .hsync(raw_hs),
        .vsync(raw_vs), .de(raw_de), .x(raw_x), .y(raw_y)
    );

    // Fade transition: manual switch requests are held until the display has
    // faded to black, then released to the control FSM at the frame boundary.
    // The bypass branch (FADE_FRAMES=0) wires next_event straight through so
    // legacy regression timing is unchanged.
    wire fade_next_event;
    wire [7:0] fade_alpha;
    assign video_fade_alpha=fade_alpha;
    wire wipe_active;
    wire [4:0] wipe_ramp;
    wire [1:0] transition_kind;
    video_fade_transition #(.FADE_FRAMES(FADE_FRAMES),.ENABLE_EMERGENCY(ENABLE_EMERGENCY)) u_fade (
        .ctrl_clk(ctrl_clk), .ctrl_rst_n(ctrl_rst_n),
        .next_event_in(next_event && !browse_active && !scene_block_controls && !clip_ctrl), .next_event_out(fade_next_event),
        .cancel_ctrl(scene_block_controls),.cancel_pix(emergency_scene_active),
        .fade_busy(fade_busy),
        .pix_clk(pix_clk), .pix_rst_n(pix_rst_n),
        .player_active(player_enable_pix), .frame_start(frame_start),
        .index_commit(index_commit), .active_index(active_index),
        .alpha_out(fade_alpha), .fade_active(video_fade_active),
        .wipe_active(wipe_active), .ramp_out(wipe_ramp),
        .transition_kind(transition_kind)
    );

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n)
            raw_vs_q <= 1'b1;
        else
            raw_vs_q <= raw_vs;
    end
    assign frame_start = raw_vs_q && !raw_vs;

    // rgb_video_adapter registers hs/vs/de/rgb by one pixel. Register x in
    // parallel so the HDMI Data Island scheduler sees the coordinate belonging
    // to the same output character, rather than the next raw VTC position.
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n)
            video_x_q <= 10'd0;
        else
            // HDMI convention: active 0..639, blank 640..799 (not zero).
            video_x_q <= raw_x >= H_BLANK ? raw_x-H_BLANK : raw_x+H_ACT;
    end
    assign video_x = video_x_q;

    media_player_control #(
        .DEFAULT_PERIOD_CYCLES(DEFAULT_PERIOD_CYCLES),
        .MIN_PERIOD_CYCLES(MIN_PERIOD_CYCLES),
        .MAX_PERIOD_CYCLES(MAX_PERIOD_CYCLES),
        .ENABLE_DIRECT_SELECT(ENABLE_THUMBNAIL_SELECT || ENABLE_EMERGENCY),
        .ENABLE_EMERGENCY(ENABLE_EMERGENCY)
    ) u_control (
        .sys_clk(ctrl_clk), .sys_rst_n(ctrl_rst_n),
        .next_event(fade_next_event && player_enable && !scene_block_controls && !clip_ctrl), .prev_event(prev_event && player_enable && !browse_active && !scene_block_controls && !clip_ctrl),
        .toggle_auto_event(toggle_auto_event && player_enable && !browse_active && !scene_block_controls && !clip_ctrl),
        .select_event(select_event && !scene_block_controls),.select_index(select_index),
        .restore_event(restore_select),.restore_index(restore_index),
        .pause_auto(scene_block_controls || browse_active || clip_ctrl || (ENABLE_THUMBNAIL_SELECT && thumbnail_toggle_event)),
        .period_cfg_valid(period_cfg_valid),
        .period_cfg_cycles(period_cfg_cycles),
        .auto_cfg_valid(auto_cfg_valid && !scene_block_controls),
        .auto_cfg_enabled(auto_cfg_enabled),
        .image_complete(normal_complete), .auto_enabled(auto_enabled),
        .active_period_cycles(active_period_cycles),
        .pending_index(pending_index), .control_error(control_error),
        .request_busy(request_busy), .pix_clk(pix_clk),
        .pix_rst_n(pix_rst_n), .frame_start(frame_start),
        .active_index(normal_index), .index_commit(index_commit)
    );

    media_frame_reader #(
        .ADDR_WIDTH(21), .IMAGE_WORDS(IMAGE_WORDS),
        .FIFO_DEPTH(FIFO_DEPTH), .FIFO_MARGIN(FIFO_MARGIN),
        .MAX_INFLIGHT_BURSTS(2), .DIAG_RETURN_PATTERN(0),
        .DIAG_SYNTH_STREAM(0), .ENABLE_THUMBNAILS(ENABLE_THUMBNAILS), .ENABLE_CLIP(ENABLE_CLIP)
    ) u_reader (
        .mem_clk(mem_clk), .mem_rst_n(mem_rst_n),
        .controller_init_done(controller_init_done && player_enable_mem),
        .controller_busy(controller_busy), .refresh_active(refresh_active),
        .app_rd_en(app_rd_en), .app_rd_addr(app_rd_addr),
        .sdram_rd_valid(sdram_rd_valid), .sdram_rd_data(sdram_rd_data),
        .pix_clk(pix_clk), .pix_rst_n(pix_rst_n),
        .frame_start(frame_start && player_enable_pix), .active_index(active_index),
        .thumbnail_mode(thumb_mode_pix),.clip_mode(clip_active),.clip_base(clip_frame_base),
        // Consume every window's stream even when its unloaded image is
        // masked black; otherwise a missing slot shifts all following slots.
        .pixel_consume(display_armed_pix && player_enable_pix && (clip_active ? clip_consume : (raw_de && (!thumb_mode_pix ||
            (ENABLE_THUMBNAIL_SELECT ? (active_x < H_ACT/2 && active_y < V_ACT/2) : thumb_de))))), .pixel_rgb(reader_rgb),
        .pixel_valid(reader_pixel_valid), .underflow(reader_underflow),
        .reader_busy(reader_busy), .frame_read_done(reader_done),
        .reader_index(reader_index), .reader_error(reader_error)
    );

    generate if(ENABLE_CRC_DIAG)begin:g_crc
        pixel_crc_probe #(.IMAGE_WORDS(IMAGE_WORDS),.SERIAL(0),
            .EXPECT0(32'h0000c596),.EXPECT1(32'h0000a66c),.EXPECT2(32'h00009937),.EXPECT3(32'h0000d073)) u_probe(
            .clk(pix_clk),.rst_n(pix_rst_n),.start(frame_start && player_enable_pix && !clip_active),.image_index(active_index),
            .data_valid(raw_de && display_armed_pix && player_enable_pix && !thumb_mode_pix && !clip_active && reader_pixel_valid),
            .pixel_rgb(reader_rgb),.checked(diag_checked),.bad(),.fault(diag_fault),.protocol_fault(),
            .fault_index(diag_index),.fault_actual(diag_actual),.fault_expected(diag_expected));
    end else begin:g_no_crc
        assign diag_checked=0;assign diag_fault=0;assign diag_index=0;assign diag_actual=0;assign diag_expected=0;
    end endgenerate

    // Fade multiplies the selected frame by the ramp alpha; an automatic
    // slideshow switch instead reveals the new frame left-to-right: pixels
    // right of the moving boundary stay black, the rest show full colour.
    // With FADE_FRAMES=0 the direct assignment keeps every pixel bit-identical
    // to the legacy path so strict regression comparisons still hold.
    wire [23:0] faded_rgb;
    generate
        if (FADE_FRAMES == 0) begin : g_fade_bypass
            assign faded_rgb = selected_rgb;
        end else begin : g_fade_mul
            // Session-level brightness folds into the transition alpha with
            // one extra 8x8 multiply, so the steady display and the fade both
            // scale together.
            // (brightness+1)/256 keeps full brightness bit-exact (256/256)
            // while lower steps land within 0.4% of brightness/255.
            wire [7:0] eff_alpha = ({8'd0, fade_alpha} * (brightness + 8'd1)) >> 8;
            wire [15:0] fade_mul_r = {8'd0, selected_rgb[23:16]} * eff_alpha;
            wire [15:0] fade_mul_g = {8'd0, selected_rgb[15:8]}  * eff_alpha;
            wire [15:0] fade_mul_b = {8'd0, selected_rgb[7:0]}   * eff_alpha;
            wire [23:0] alpha_rgb =
                // Preserve the validated picture at full brightness instead
                // of losing one level through the template's /256 scaling.
                (eff_alpha == 8'd255) ? selected_rgb :
                {fade_mul_r[15:8], fade_mul_g[15:8], fade_mul_b[15:8]};
            // Reveal boundary advances one H_ACT/FADE_FRAMES column step per
            // frame; the comparison uses the same raw_x that aligns with
            // selected_rgb at this point in the pipeline.
            localparam integer WIPE_STEP = H_ACT / FADE_FRAMES;
            wire [9:0] wipe_boundary = wipe_ramp * WIPE_STEP;
            wire [6:0] blind_x_boundary = wipe_ramp * 4;
            reg transition_pixel;
            always @* begin
                case (transition_kind)
                    2'd0: transition_pixel = active_x[9:0] < wipe_boundary;
                    2'd1: transition_pixel = active_x[9:0] >= H_ACT - wipe_boundary;
                    2'd2: transition_pixel = {1'b0, active_x[5:0]} < blind_x_boundary;
                    default: transition_pixel = (active_x[6] ^ raw_y[6]) ?
                        ({1'b0, active_x[5:0]} < blind_x_boundary) :
                        ({1'b0, active_x[5:0]} >= 7'd64 - blind_x_boundary);
                endcase
            end
            assign faded_rgb = wipe_active ?
                (transition_pixel ? alpha_rgb : 24'h000000) :
                alpha_rgb;
        end
    endgenerate

    rgb_video_adapter u_video_adapter (
        .pclk(pix_clk), .rst_n(pix_rst_n), .hs_in(raw_hs),
        .vs_in(raw_vs), .de_in(raw_de && display_armed_pix),
        .rgb_in(clip_active ? selected_rgb : emergency_scene_active ? (emergency_missing ? 24'h300000 : selected_rgb) :
            thumb_mode_pix ? ((ENABLE_EMERGENCY && active_x>=H_ACT/4 && active_x<H_ACT/2 && active_y>=V_ACT/4 && active_y<V_ACT/2) ? 24'h802020 :
            (thumb_de ? (thumb_border ? 24'hffff00 : selected_rgb) : 24'h000000)) : faded_rgb), .video_clk(video_clk),
        .video_hs(video_hs), .video_vs(video_vs),
        .video_de(video_de), .video_rgb(video_rgb)
    );

    assign video_error = reader_error_pix2 != 0 ? reader_error_pix2 :
                         reader_underflow ? 8'h63 : control_error_pix2;
endmodule
