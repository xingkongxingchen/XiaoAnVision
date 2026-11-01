`timescale 1ns/1ps

// Player-owned boundary between the registered video bundle and the verified
// Route B HDMI packet/symbol chain. The EG4 DDR PHY remains in the board Top so
// this bridge can be exercised in ordinary RTL simulation without vendor pads.
// media_id drives the per-image tone selection and volume scales the output,
// turning the tone source into the audio half of the AV-linked feature.
module media_hdmi_audio_bridge #(parameter integer ENABLE_WAV=0,ENABLE_EMERGENCY=0,DUAL_MUSIC=0,ENABLE_MASTER_VOLUME=0) (
    input  wire        pixel_clk,
    input  wire        pixel_rst_n,
    input  wire        video_hsync,
    input  wire        video_vsync,
    input  wire        video_de,
    input  wire        video_de_lookahead,
    input  wire [9:0]  video_x,
    input  wire [23:0] video_rgb,
    input  wire [1:0]  media_id,
    input  wire [7:0]  volume,
    input  wire [7:0]  master_volume,
    input  wire wav_valid,wav_active,
    input  wire signed [15:0] wav_sample,
    input  wire [7:0] fade_gain,
    input  wire emergency,
    input  wire alert_valid,
    input  wire signed[15:0] alert_sample,
    output wire alert_ready,
    output wire wav_ready,wav_tick,
    output wire [9:0]  channel0_symbol,
    output wire [9:0]  channel1_symbol,
    output wire [9:0]  channel2_symbol,
    output wire        sequence_error,
    output wire        tone_overflow,
    output wire        pcm_contract_error,
    output wire        blip_active,
    output wire        pcm_tap_valid,
    output wire signed [15:0] pcm_tap_left
);
    wire source_valid;
    wire source_ready;
    wire signed [15:0] source_left;
    wire signed [15:0] source_right;
    wire tone_valid,tone_ready;
    wire tone_error,emergency_overflow;
    assign tone_overflow=tone_error || emergency_overflow;
    wire signed [15:0] tone_left,tone_right;
    wire tone_rst_n=pixel_rst_n && !((ENABLE_WAV!=0) && wav_active);
    wire sample_valid;
    wire sample_ready;
    wire signed [15:0] sample_left;
    wire signed [15:0] sample_right;

    reg video_hsync_q;
    reg video_vsync_q;
    reg video_de_q;
    reg video_de_lookahead_q;
    reg [9:0] video_x_q;
    reg [23:0] video_rgb_q;
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            video_hsync_q <= 1'b1;
            video_vsync_q <= 1'b1;
            video_de_q <= 1'b0;
            video_de_lookahead_q <= 1'b0;
            video_x_q <= 10'd0;
            video_rgb_q <= 24'h000000;
        end else begin
            video_hsync_q <= video_hsync;
            video_vsync_q <= video_vsync;
            video_de_q <= video_de;
            video_de_lookahead_q <= video_de_lookahead;
            video_x_q <= video_x;
            video_rgb_q <= video_de ? video_rgb : 24'h000000;
        end
    end

    pcm_media_tone u_tone (
        .clk(pixel_clk), .rst_n(tone_rst_n),
        .media_id(media_id), .volume(volume),
        .sample_valid(tone_valid), .sample_ready(tone_ready),
        .sample_left(tone_left), .sample_right(tone_right),
        .overflow(tone_error), .blip_active(blip_active)
    );

    generate if(ENABLE_WAV!=0)begin:g_wav
        reg[24:0] rate_accumulator;
        assign wav_tick=rate_accumulator>=25000000-48000;
        always @(posedge pixel_clk or negedge pixel_rst_n)begin
            if(!pixel_rst_n)rate_accumulator<=0;
            else if(wav_tick)rate_accumulator<=rate_accumulator+48000-25000000;
            else rate_accumulator<=rate_accumulator+48000;
        end
        wire signed[24:0] wav_scaled=wav_sample*$signed({1'b0,volume});
        wire signed[15:0] wav_level=wav_scaled >>> 8;
        wire signed[15:0] mux_left,mux_right;
        wire mux_valid,mux_ready;
        reg held_valid;
        reg signed[15:0] held_left,held_right;
        wire held_ready;
        assign mux_ready=!held_valid || held_ready;
        audio_source_mux u_source(
            .clk(pixel_clk),.rst_n(pixel_rst_n),.wav_valid(wav_valid),.wav_ready(wav_ready),
            .wav_left(wav_level),.wav_right(wav_level),.wav_active(wav_active),
            .arp_valid(tone_valid),.arp_ready(tone_ready),.arp_left(tone_left),.arp_right(tone_right),
            .force_arpeggio(1'b0),.out_valid(mux_valid),.out_ready(mux_ready),
            .out_left(mux_left),.out_right(mux_right));
        wire signed[24:0] gain_left=mux_left*$signed({1'b0,fade_gain});
        wire signed[24:0] gain_right=mux_right*$signed({1'b0,fade_gain});
        // Freeze scaled PCM until accepted, even if the frame gain changes.
        always @(posedge pixel_clk or negedge pixel_rst_n)begin
            if(!pixel_rst_n)begin held_valid<=0;held_left<=0;held_right<=0;end
            else if(mux_ready)begin
                held_valid<=mux_valid;
                if(mux_valid)begin
                    held_left<=fade_gain==255 ? mux_left : gain_left >>> 8;
                    held_right<=fade_gain==255 ? mux_right : gain_right >>> 8;
                end
            end
        end
        if(ENABLE_EMERGENCY)begin:g_emergency
            emergency_audio_mix #(.DUAL_MUSIC(DUAL_MUSIC),.FADE_BITS(DUAL_MUSIC ? 10 : 8)) u_mix(.clk(pixel_clk),.rst_n(pixel_rst_n),.sample_tick(wav_tick),.emergency(emergency),
                .alert_valid(alert_valid),.alert_sample(alert_sample),.alert_ready(alert_ready),
                .normal_valid(held_valid),.normal_ready(held_ready),.normal_left(held_left),.normal_right(held_right),
                .out_valid(source_valid),.out_ready(source_ready),.out_left(source_left),.out_right(source_right),.overflow(emergency_overflow));
        end else begin:g_normal
            assign alert_ready=1'b0;
            assign held_ready=source_ready;assign emergency_overflow=0;
            assign source_valid=held_valid;
            assign source_left=held_left;assign source_right=held_right;
        end
    end else begin:g_tone_only
        assign alert_ready=1'b0;
        assign emergency_overflow=0;
        assign source_valid=tone_valid;
        assign source_left=tone_left;assign source_right=tone_right;
        assign tone_ready=source_ready;
        assign wav_ready=0;assign wav_tick=0;
    end endgenerate

    wire final_valid,final_ready;
    wire signed[15:0]final_left,final_right;
    generate if(ENABLE_MASTER_VOLUME)begin:g_master
        pcm_master_volume u_volume(.clk(pixel_clk),.rst_n(pixel_rst_n),.sample_tick(wav_tick),
            .volume(master_volume),.in_valid(source_valid),.in_ready(source_ready),
            .in_left(source_left),.in_right(source_right),.out_valid(final_valid),.out_ready(final_ready),
            .out_left(final_left),.out_right(final_right));
    end else begin:g_unity
        assign final_valid=source_valid;assign source_ready=final_ready;
        assign final_left=source_left;assign final_right=source_right;
    end endgenerate
    m06_pcm_contract_adapter u_m06_pcm_contract (
        .clk(pixel_clk), .rst_n(pixel_rst_n),
        .source_valid(final_valid), .source_ready(final_ready),
        .source_left(final_left), .source_right(final_right),
        .pcm_valid(sample_valid), .pcm_ready(sample_ready),
        .pcm_left(sample_left), .pcm_right(sample_right),
        .contract_error(pcm_contract_error)
    );

    hdmi_audio_symbol_core u_symbol_core (
        .pixel_clk(pixel_clk), .rst_n(pixel_rst_n),
        .video_hsync(video_hsync_q), .video_vsync(video_vsync_q),
        .video_de(video_de_q), .video_x(video_x_q), .video_rgb(video_rgb_q),
        .video_de_lookahead(video_de_lookahead_q),
        .sample_valid(sample_valid), .sample_ready(sample_ready),
        .sample_left(sample_left), .sample_right(sample_right),
        .channel0_symbol(channel0_symbol),
        .channel1_symbol(channel1_symbol),
        .channel2_symbol(channel2_symbol),
        .sequence_error(sequence_error)
    );

    assign pcm_tap_valid = sample_valid && sample_ready;
    assign pcm_tap_left = sample_left;
endmodule
