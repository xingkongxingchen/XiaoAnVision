`timescale 1ns/1ps

module promax_audio_waveform #(
    parameter integer WAVE_X = 24,
    parameter integer WAVE_Y = 392,
    parameter integer WAVE_WIDTH = 576,
    parameter integer WAVE_HEIGHT = 64,
    parameter integer DECIMATE = 12
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        de,
    input  wire [23:0] rgb_in,
    input  wire [9:0]  pixel_x,
    input  wire        enable,
    input  wire        pcm_tap_valid,
    input  wire signed [15:0] pcm_tap_left,
    output wire [23:0] rgb_out,
    output wire        waveform_active
);
    localparam integer SAMPLE_COUNT = 32;
    localparam integer SAMPLE_SPACING = WAVE_WIDTH / SAMPLE_COUNT;
    localparam integer CENTER_Y = WAVE_Y + WAVE_HEIGHT/2;

    reg [11:0] line_y;
    reg de_q;
    reg vs_q;
    wire frame_start = vs_q && !vsync;

    // Mapped offsets are -30..30, so six signed bits are sufficient.
    reg signed [5:0] sample_bank0 [0:SAMPLE_COUNT-1];
    reg signed [5:0] sample_bank1 [0:SAMPLE_COUNT-1];
    reg write_bank;
    reg display_bank;
    reg display_valid;
    reg [5:0] capture_count;
    reg [7:0] decimate_count;
    reg [7:0] peak_bank0;
    reg [7:0] peak_bank1;
    reg [7:0] display_peak;
    // Keep the strongest signed sample in each 12-sample (250us) window.
    // Taking only one point can miss periodic peaks entirely.
    wire [15:0] magnitude = pcm_tap_left[15] ? -pcm_tap_left : pcm_tap_left;
    wire [7:0] sample_abs = magnitude[15:8];
    reg [15:0] window_peak;
    reg signed [5:0] window_sample;
    // Static display-only companding BEFORE quantization. Low amplitudes have
    // 64 PCM units/pixel instead of 256; larger signals compress into +/-30px.
    // No AGC, minimum animated amplitude, or change to the actual audio stream.
    function [7:0] visual_height;
        input [15:0] level;
        reg [7:0] height;
        begin
            if (level < 1024) height = {4'd0,level[9:6]};
            else if (level < 4096) height = 8'd12 + {4'd0,level[11:8]};
            else if (level < 12288) height = 8'd28;
            else if (level < 20480) height = 8'd29;
            else height = 8'd30;
            visual_height = height > WAVE_HEIGHT/2-2 ? WAVE_HEIGHT/2-2 : height;
        end
    endfunction
    wire signed [5:0] visual_sample = pcm_tap_left[15] ?
                                   -$signed(visual_height(magnitude)) :
                                    $signed(visual_height(magnitude));
    wire [15:0] next_peak = magnitude >= window_peak ? magnitude : window_peak;
    wire signed [5:0] next_sample = magnitude >= window_peak ?
                                   visual_sample : window_sample;
    wire [7:0] frame_peak = write_bank ? peak_bank1 : peak_bank0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_y <= 12'd0;
            de_q <= 1'b0;
            vs_q <= 1'b1;
            write_bank <= 1'b0;
            display_bank <= 1'b1;
            display_valid <= 1'b0;
            capture_count <= 6'd0;
            decimate_count <= 8'd0;
            peak_bank0 <= 8'd0;
            peak_bank1 <= 8'd0;
            display_peak <= 8'd0;
            window_peak <= 0;
            window_sample <= 0;
        end else begin
            de_q <= de;
            vs_q <= vsync;
            if (!vsync)
                line_y <= 12'd0;
            else if (de_q && !de)
                line_y <= line_y + 1'b1;

            if (frame_start) begin
                if (capture_count == SAMPLE_COUNT) begin
                    display_bank <= write_bank;
                    display_valid <= 1'b1;
                    write_bank <= ~write_bank;
                end
                // Fast attack, ~0.54s full-range release at 60fps. Peak uses
                // ALL accepted samples, including those after waveform capture.
                if (frame_peak >= display_peak) display_peak <= frame_peak;
                else if (display_peak > 4 && display_peak-4 > frame_peak)
                    display_peak <= display_peak-4;
                else display_peak <= frame_peak;
                if (capture_count == 0) display_valid <= 1'b0;
                capture_count <= 6'd0;
                decimate_count <= 8'd0;
                window_peak <= 0;
                window_sample <= 0;
                // Clear the bank that will actually capture the next frame.
                // An incomplete capture does not swap banks.
                if (capture_count == SAMPLE_COUNT) begin
                    if (write_bank) peak_bank0 <= 8'd0;
                    else peak_bank1 <= 8'd0;
                end else begin
                    if (write_bank) peak_bank1 <= 8'd0;
                    else peak_bank0 <= 8'd0;
                end
            end else if (pcm_tap_valid) begin
                if (write_bank) begin
                    if (sample_abs > peak_bank1) peak_bank1 <= sample_abs;
                end else begin
                    if (sample_abs > peak_bank0) peak_bank0 <= sample_abs;
                end
                if (capture_count < SAMPLE_COUNT) begin
                if (decimate_count == DECIMATE-1) begin
                    if (write_bank)
                        sample_bank1[capture_count] <= next_sample;
                    else
                        sample_bank0[capture_count] <= next_sample;
                    capture_count <= capture_count + 1'b1;
                    decimate_count <= 0;
                    window_peak <= 0;
                    window_sample <= 0;
                end else begin
                    decimate_count <= decimate_count + 1'b1;
                    window_peak <= next_peak;
                    window_sample <= next_sample;
                end
                end
            end
        end
    end

    // Render coordinates are bounded by the 10-bit screen input. Keep the
    // constant division and signed sample math narrow instead of 32-bit ints.
    localparam [9:0] SAMPLE_STEP = SAMPLE_SPACING;
    wire [9:0] relative_x = pixel_x - WAVE_X;
    reg [5:0] sample_index;
    reg signed [5:0] sample_value;
    reg [9:0] sample_y;
    reg [9:0] peak_height;
    reg signed [5:0] selected_sample;
    reg wave_pixel;
    reg outline_pixel;
    reg axis_pixel;
    reg peak_pixel;

    always @* begin
        sample_index = 0;
        selected_sample = 6'sd0;
        sample_value = 0;
        sample_y = CENTER_Y;
        peak_height = display_peak > WAVE_HEIGHT-1 ? WAVE_HEIGHT-1 : display_peak;
        wave_pixel = 1'b0;
        outline_pixel = 1'b0;
        axis_pixel = 1'b0;
        peak_pixel = 1'b0;

        if (enable && de && pixel_x >= WAVE_X &&
            pixel_x < WAVE_X + WAVE_WIDTH &&
            line_y >= WAVE_Y && line_y < WAVE_Y + WAVE_HEIGHT) begin
            axis_pixel = (line_y == CENTER_Y);
            sample_index = relative_x / SAMPLE_STEP;
            if (display_valid && sample_index < SAMPLE_COUNT) begin
                selected_sample = display_bank ?
                                  sample_bank1[sample_index] : sample_bank0[sample_index];
                sample_value = $signed(selected_sample);
                // Samples are already mapped and bounded before storage.
                sample_y = CENTER_Y - sample_value;
                // 2px bright ink plus a 1px edge each side: 4px total, not 7px.
                wave_pixel = (line_y >= sample_y-1 && line_y <= sample_y);
                outline_pixel = (line_y >= sample_y-2 && line_y <= sample_y+1);
            end
        end

        if (enable && de && pixel_x >= WAVE_X+WAVE_WIDTH+8 &&
            pixel_x < WAVE_X+WAVE_WIDTH+16 &&
            line_y >= WAVE_Y+WAVE_HEIGHT-peak_height &&
            line_y < WAVE_Y+WAVE_HEIGHT)
            peak_pixel = 1'b1;
    end

    assign waveform_active = wave_pixel || outline_pixel || axis_pixel || peak_pixel;
    assign rgb_out = wave_pixel ? 24'h20ff90 :
                     outline_pixel ? 24'h10382c :
                     peak_pixel ? 24'hffb020 :
                     axis_pixel ? 24'h406060 : rgb_in;
endmodule
