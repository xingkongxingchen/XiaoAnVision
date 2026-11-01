`timescale 1ns/1ps

// 24-bit RGB wrapper around the 12-bit status OSD. The overlay core is
// purely combinational, so this stage adds no pipeline delay and the
// video_x/video_de alignment used by the HDMI Data Island scheduler is
// untouched. A local line counter reconstructs pixel_y from the video
// sync/de bundle so the video pipeline needs no extra output port.
module osd_overlay_24 #(
    parameter integer OSD_X = 16,
    parameter integer OSD_Y = 16,
    parameter integer ENABLE_PICTURE_PARAMS = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        de,
    input  wire [23:0] rgb_in,
    input  wire [9:0]  pixel_x,
    input  wire [1:0]  active_index,
    input  wire        auto_enabled,
    input  wire [7:0]  error_code,
    input  wire [7:0]  picture_brightness,picture_contrast,
    input  wire        picture_menu,
    output wire [23:0] rgb_out,
    output wire        de_out,
    output wire        osd_active
);
    reg [11:0] line_y;
    reg de_q;
    reg vs_q;
    wire frame_start = vs_q && !vsync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_y <= 12'd0;
            de_q <= 1'b0;
            vs_q <= 1'b1;
        end else begin
            de_q <= de;
            vs_q <= vsync;
            // vsync is active low: hold the line counter at zero through the
            // sync pulse so the first active line after back porch is row 0.
            if (!vsync)
                line_y <= 12'd0;
            else if (de_q && !de)
                line_y <= line_y + 1'b1;
        end
    end

    wire [11:0] osd_rgb12;
    wire osd_hit;

    status_osd_overlay #(
        .OSD_X(OSD_X/2),
        .OSD_Y(OSD_Y/2)
    ) u_osd (
        .clk(clk), .rst_n(rst_n),
        .frame_start(frame_start),
        .active_index(active_index), .auto_enabled(auto_enabled),
        .error_code(error_code),
        .in_de(de),
        .in_rgb({rgb_in[23:20], rgb_in[15:12], rgb_in[7:4]}),
        .pixel_x({3'b000, pixel_x[9:1]}),
        .pixel_y({1'b0,line_y[11:1]}),
        .out_rgb(osd_rgb12),
        .out_de(),
        .osd_pixel(osd_hit)
    );

    // Non-OSD pixels pass the original 24-bit value through untouched;
    // Status glyphs use full red; non-OSD pixels remain untouched.
    wire[23:0]status_rgb = osd_hit ? 24'hff0000 : rgb_in;
    generate if(ENABLE_PICTURE_PARAMS)begin : g_params
        picture_params_osd u_params(.in_de(de),.rgb_in(status_rgb),.pixel_x(pixel_x),
            .pixel_y(line_y),.brightness(picture_brightness),.contrast(picture_contrast),
            .menu_mode(picture_menu),.rgb_out(rgb_out));
    end else begin : g_no_params
        assign rgb_out=status_rgb;
    end endgenerate
    assign de_out = de;
    assign osd_active = osd_hit;
endmodule
