`timescale 1ns/1ps

module promax_text_overlay #(
    parameter integer PARAM_X = 8,
    parameter integer PARAM_Y = 40,
    parameter integer SUBTITLE_Y = 72,
    parameter integer H_ACTIVE = 640,
    parameter integer ENABLE_PARAMS = 1,
    parameter integer MAX_SUBTITLE_CHARS = 12,
    parameter integer EXTERNAL_RESTART = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        de,
    input  wire [23:0] rgb_in,
    input  wire [9:0]  pixel_x,
    input  wire        enable,
    input  wire        subtitle_enable,
    input  wire [8*MAX_SUBTITLE_CHARS-1:0] subtitle_text,
    input  wire restart_toggle,
    input  wire [5:0]  subtitle_length,
    input  wire [7:0]  brightness,
    input  wire [7:0]  volume,
    input  wire [31:0] period_ms,
    input  wire        auto_enabled,
    input  wire        source_scale_2x,
    output wire [23:0] rgb_out,
    output wire        overlay_active
);
    localparam integer CELL_W = 12;
    localparam integer CELL_H = 16;
    localparam integer SUBTITLE_CELL_W = 18;
    localparam integer SUBTITLE_CELL_H = 18;
    localparam integer PARAM_CHARS = 32;
    localparam integer SCROLL_CYCLE = H_ACTIVE + MAX_SUBTITLE_CHARS*SUBTITLE_CELL_W;
    reg [8*MAX_SUBTITLE_CHARS-1:0] subtitle_text_frame;
    reg [5:0] subtitle_length_frame;
    reg subtitle_enable_frame,restart_frame;
    // Width changes only with the frame-latched length. Capture both together
    // so pixel rendering does not include the length-to-width multiplier.
    reg [10:0] subtitle_width;
    wire [10:0] scroll_limit = EXTERNAL_RESTART ? H_ACTIVE+subtitle_width : SCROLL_CYCLE;

    reg [11:0] line_y;
    reg de_q;
    reg vs_q;
    reg [10:0] scroll_pos;
    reg [1:0] scroll_div;
    reg [7:0] brightness_frame;
    reg [7:0] volume_frame;
    reg [31:0] period_frame;
    reg auto_frame;
    reg source_scale_2x_frame;
    wire frame_start = vs_q && !vsync;
    // Frame-constant base is independent of X. Compute the two X additions
    // in parallel; no state or video latency is added to this interface.
    wire signed [12:0] subtitle_wrap_base = $signed({2'b00,scroll_pos}) - $signed({2'b00,scroll_limit});
    wire signed [12:0] subtitle_wrapped_x = $signed({3'b000,pixel_x}) + subtitle_wrap_base;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_y <= 12'd0;
            de_q <= 1'b0;
            vs_q <= 1'b1;
            scroll_pos <= 10'd0;
            scroll_div <= 2'd0;
            subtitle_text_frame <= 0;
            subtitle_length_frame <= 0;
            subtitle_width <= 0;
            subtitle_enable_frame <= 1;
            restart_frame <= 0;
            brightness_frame <= 8'd255;
            volume_frame <= 8'd255;
            period_frame <= 32'd5000;
            auto_frame <= 1'b0;
            source_scale_2x_frame <= 1'b0;
        end else begin
            de_q <= de;
            vs_q <= vsync;
            if (!vsync)
                line_y <= 12'd0;
            else if (de_q && !de)
                line_y <= line_y + 1'b1;

            if (frame_start) begin
                subtitle_text_frame <= subtitle_text;
                subtitle_length_frame <= subtitle_length > MAX_SUBTITLE_CHARS ? MAX_SUBTITLE_CHARS : subtitle_length;
                subtitle_width <= (subtitle_length > MAX_SUBTITLE_CHARS ? MAX_SUBTITLE_CHARS : subtitle_length) * SUBTITLE_CELL_W;
                subtitle_enable_frame <= subtitle_enable;
                restart_frame <= restart_toggle;
                brightness_frame <= brightness;
                volume_frame <= volume;
                period_frame <= period_ms;
                auto_frame <= auto_enabled;
                source_scale_2x_frame <= source_scale_2x;
                if (EXTERNAL_RESTART && restart_frame != restart_toggle) begin
                    scroll_pos <= 0;
                    scroll_div <= 0;
                end else if (scroll_div == 2'd2) begin
                    scroll_div <= 2'd0;
                    scroll_pos <= (scroll_pos >= scroll_limit-1) ?
                                  11'd0 : scroll_pos + 1'b1;
                end else begin
                    scroll_div <= scroll_div + 1'b1;
                end
            end
        end
    end

    function [7:0] decimal_hundreds;
        input [7:0] value;
        begin
            decimal_hundreds = "0" + value / 100;
        end
    endfunction

    localparam [255:0] CN_GLYPH_0 = 256'b0000000110000000000100011000110000011001100110000000110110010000000010011001000000000001100000000111111111111110000000111100000000000111111000000000010110110000000011011001100000111001100011100110000110000010000000011000000000000001100000000000000000000000;
    localparam [255:0] CN_GLYPH_1 = 256'b0000000000101000011111110010100000010100111111100001010000101000011111100010100001010110111111100101011000000000010101100000000001100110011111000100001001000100011111100111110001000010010001000100001001000100011111100111110001000010010000000000000000000000;
    localparam [255:0] CN_GLYPH_2 = 256'b0000000100000000000000010000000000000001000000000011111111111000001000010000100000100001000010000011111111111000001000010000100000100001000010000011111111111000001111111111100000100001000000000000000100000010000000011111111000000000000000000000000000000000;
    localparam [255:0] CN_GLYPH_3 = 256'b0000000000000000001111111111110000000000001110000000000001100000000000011000000000000001100000000111111111111110011111111111100000000001100000000000000110000000000000011000000000000001100000000000000110000000000001110000000000000000000000000000000000000000;
    localparam [255:0] CN_GLYPH_4 = 256'b0000000000000000001111111111110000000001100000000000000110000000000000011000000000000001100000000000000110000000000000011000000000000001100000000000000110000000000000011000000000000001100000000111111111111110000000000000000000000000000000000000000000000000;
    localparam [255:0] CN_GLYPH_5 = 256'b0000110011000000000010001000000000011001100000000001000111111110001100110100000000110110010000000101000001111100010100000100000000010000010000000001000001000000000100000111111000010000010000000001000001000000000100000100000000010000010000000000000000000000;
    localparam [255:0] CN_GLYPH_6 = 256'b0000000100000000000000011000000001111111111111000110000000000100011000000000010000011111111110000000011000110000000011000001100000011111111011000000000110000000000111111111100000000001100000000000000110000000011111111111111000000000000000000000000000000000;
    localparam [255:0] CN_GLYPH_7 = 256'b0001000001000000000100000100100000010000010011000001010001001000011101011111111001010010011100000101000001110000000100000111000000010000111100000001000010110000000100001011000000010001101100000001001100110010000101100001111000000000000000000000000000000000;
    localparam [255:0] CN_GLYPH_8 = 256'b0000110000000000000010000011111001111111101001000001100000100100000100000010010000111111001001000111000100101100010111110010010000010001001000100001000100100010000111110010001000010001001011100001000100100000000100110010000000000000001000000000000000000000;

    function [15:0] chinese_glyph_row;
        input [3:0] glyph_id;
        input [3:0] row;
        reg [255:0] glyph_bits;
        begin
            case (glyph_id)
                4'd0: glyph_bits = CN_GLYPH_0;
                4'd1: glyph_bits = CN_GLYPH_1;
                4'd2: glyph_bits = CN_GLYPH_2;
                4'd3: glyph_bits = CN_GLYPH_3;
                4'd4: glyph_bits = CN_GLYPH_4;
                4'd5: glyph_bits = CN_GLYPH_5;
                4'd6: glyph_bits = CN_GLYPH_6;
                4'd7: glyph_bits = CN_GLYPH_7;
                4'd8: glyph_bits = CN_GLYPH_8;
                // Fixed SimSun 16-pixel glyphs: U+9ED8, U+8BA4 (default).
                4'd9: glyph_bits = 256'h0020fe289224d624ba2093fefe201020fe2010501e50e0500288aa88a9048202;
                4'd10: glyph_bits = 256'h004020401040104000400040f040104010a010a010a015101910120804040802;
                default: glyph_bits = 256'b0;
            endcase
            chinese_glyph_row = glyph_bits[255-row*16 -: 16];
        end
    endfunction

    function [7:0] decimal_tens;
        input [7:0] value;
        begin
            decimal_tens = "0" + (value % 100) / 10;
        end
    endfunction

    function [7:0] decimal_ones;
        input [7:0] value;
        begin
            decimal_ones = "0" + value % 10;
        end
    endfunction

    function [7:0] param_char;
        input integer index;
        reg [7:0] bright_percent;
        reg [7:0] period_seconds;
        begin
            case (brightness_frame)
                8'd255: bright_percent = 8'd100;
                8'd192: bright_percent = 8'd75;
                8'd128: bright_percent = 8'd50;
                default: bright_percent = 8'd25;
            endcase
            if (period_frame >= 30000)
                period_seconds = 8'd30;
            else if (period_frame >= 10000)
                period_seconds = 8'd10;
            else if (period_frame >= 5000)
                period_seconds = 8'd5;
            else
                period_seconds = 8'd2;

            case (index)
                0: param_char = "B";  1: param_char = "R";
                2: param_char = "T";
                3: param_char = decimal_hundreds(bright_percent);
                4: param_char = decimal_tens(bright_percent);
                5: param_char = decimal_ones(bright_percent);
                6: param_char = " ";  7: param_char = "V";
                8: param_char = "O";  9: param_char = "L";
                10: param_char = decimal_hundreds(volume_frame);
                11: param_char = decimal_tens(volume_frame);
                12: param_char = decimal_ones(volume_frame);
                13: param_char = " ";  14: param_char = "P";
                15: param_char = decimal_tens(period_seconds);
                16: param_char = decimal_ones(period_seconds);
                17: param_char = "S"; 18: param_char = " ";
                19: param_char = "M"; 20: param_char = ":";
                21: param_char = auto_frame ? "A" : "M";
                22: param_char = source_scale_2x_frame ? "1" : "6";
                23: param_char = source_scale_2x_frame ? "2" : "4";
                24: param_char = source_scale_2x_frame ? "8" : "0";
                25: param_char = source_scale_2x_frame ? "0" : "X";
                26: param_char = source_scale_2x_frame ? "X" : "4";
                27: param_char = source_scale_2x_frame ? "9" : "8";
                28: param_char = source_scale_2x_frame ? "6" : "0";
                29: param_char = source_scale_2x_frame ? "0" : " ";
                default: param_char = " ";
            endcase
        end
    endfunction

    function [7:0] subtitle_char;
        input integer index;
        begin
            if (index >= 0 && index < subtitle_length_frame)
                subtitle_char = subtitle_text_frame[index*8 +: 8];
            else
                subtitle_char = " ";
        end
    endfunction

    // Complete printable ASCII, retaining the original MiCu capital/digit font.
    function [4:0] extra_glyph_row;
        input [7:0] character;
        input [2:0] row;
        reg [34:0] bits;
        begin
            case(character)
                8'h22: bits = 35'b01010010100101000000000000000000000;
                8'h23: bits = 35'b01010111110101001010111110101000000;
                8'h24: bits = 35'b00100011111010001110001011111000100;
                8'h25: bits = 35'b11000110010001000100010001001100011;
                8'h26: bits = 35'b01100100101010001000101011001001101;
                8'h27: bits = 35'b00100001000100000000000000000000000;
                8'h28: bits = 35'b00010001000100001000010000010000010;
                8'h29: bits = 35'b01000001000001000010000100010001000;
                8'h40: bits = 35'b01110100011011110101101111000001110;
                8'h60: bits = 35'b01000001000001000000000000000000000;
                8'h61: bits = 35'b00000000000111000001011111000101111;
                8'h62: bits = 35'b10000100001011011001100011000111110;
                8'h63: bits = 35'b00000000000111010000100001000101110;
                8'h64: bits = 35'b00001000010110110011100011000101111;
                8'h65: bits = 35'b00000000000111010001111111000001110;
                8'h66: bits = 35'b00110010010100011100010000100001000;
                8'h67: bits = 35'b00000011111000110001011110000101110;
                8'h68: bits = 35'b10000100001011011001100011000110001;
                8'h69: bits = 35'b00100000000110000100001000010001110;
                8'h70: bits = 35'b00000111101000110001111101000010000;
                8'h71: bits = 35'b00000011111000110001011110000100001;
                8'h72: bits = 35'b00000000001011011001100001000010000;
                8'h73: bits = 35'b00000000000111110000011100000111110;
                8'h74: bits = 35'b01000010001110001000010000100100110;
                8'h75: bits = 35'b00000000001000110001100011001101101;
                8'h76: bits = 35'b00000000001000110001100010101000100;
                8'h77: bits = 35'b00000000001000110001101011010101010;
                8'h78: bits = 35'b00000000001000101010001000101010001;
                8'h79: bits = 35'b00000100011000110001011110000101110;
                8'h2a: bits = 35'b00000101010111011111011101010100000;
                8'h2b: bits = 35'b00000001000010011111001000010000000;
                8'h3b: bits = 35'b00000001000010000000001000010001000;
                8'h3c: bits = 35'b00010001000100010000010000010000010;
                8'h3d: bits = 35'b00000000001111100000111110000000000;
                8'h3e: bits = 35'b01000001000001000001000100010001000;
                8'h5b: bits = 35'b01110010000100001000010000100001110;
                8'h5c: bits = 35'b10000010000100000100000100001000001;
                8'h5d: bits = 35'b01110000100001000010000100001001110;
                8'h5e: bits = 35'b00100010101000100000000000000000000;
                8'h6a: bits = 35'b00010000000011000010000101001001100;
                8'h6b: bits = 35'b10000100001001010100110001010010010;
                8'h6c: bits = 35'b01100001000010000100001000010001110;
                8'h6d: bits = 35'b00000000001101010101101011010110101;
                8'h6e: bits = 35'b00000000001011011001100011000110001;
                8'h6f: bits = 35'b00000000000111010001100011000101110;
                8'h7a: bits = 35'b00000000001111100010001000100011111;
                8'h7b: bits = 35'b00011001000010001000001000010000011;
                8'h7c: bits = 35'b00100001000010000100001000010000100;
                8'h7d: bits = 35'b11000001000010000010001000010011000;
                8'h7e: bits = 35'b00000000000100110110000000000000000;
                default: bits = 0;
            endcase
            extra_glyph_row = row < 7 ? (bits >> ((6-row)*5)) : 5'd0;
        end
    endfunction

    function [4:0] glyph_row;
        input [7:0] character;
        input [2:0] row;
        begin
            glyph_row = 5'b00000;
            case (character)
                "0": case(row) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10011;3:glyph_row=5'b10101;4:glyph_row=5'b11001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "1": case(row) 0:glyph_row=5'b00100;1:glyph_row=5'b01100;2:glyph_row=5'b00100;3:glyph_row=5'b00100;4:glyph_row=5'b00100;5:glyph_row=5'b00100;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "2": case(row) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b00001;3:glyph_row=5'b00010;4:glyph_row=5'b00100;5:glyph_row=5'b01000;6:glyph_row=5'b11111;default:glyph_row=0;endcase
                "3": case(row) 0:glyph_row=5'b11110;1:glyph_row=5'b00001;2:glyph_row=5'b00001;3:glyph_row=5'b01110;4:glyph_row=5'b00001;5:glyph_row=5'b00001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                "4": case(row) 0:glyph_row=5'b00010;1:glyph_row=5'b00110;2:glyph_row=5'b01010;3:glyph_row=5'b10010;4:glyph_row=5'b11111;5:glyph_row=5'b00010;6:glyph_row=5'b00010;default:glyph_row=0;endcase
                "5": case(row) 0:glyph_row=5'b11111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b11110;4:glyph_row=5'b00001;5:glyph_row=5'b00001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                "6": case(row) 0:glyph_row=5'b01110;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b11110;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "7": case(row) 0:glyph_row=5'b11111;1:glyph_row=5'b00001;2:glyph_row=5'b00010;3:glyph_row=5'b00100;4:glyph_row=5'b01000;5:glyph_row=5'b01000;6:glyph_row=5'b01000;default:glyph_row=0;endcase
                "8": case(row) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b01110;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "9": case(row) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b01111;4:glyph_row=5'b00001;5:glyph_row=5'b00001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "A": case(row) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11111;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "B": case(row) 0:glyph_row=5'b11110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11110;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                "C": case(row) 0:glyph_row=5'b01111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b10000;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b01111;default:glyph_row=0;endcase
                "D": case(row) 0:glyph_row=5'b11110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b10001;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                "E": case(row) 0:glyph_row=5'b11111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b11110;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b11111;default:glyph_row=0;endcase
                "F": case(row) 0:glyph_row=5'b11111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b11110;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b10000;default:glyph_row=0;endcase
                "G": case(row) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10000;3:glyph_row=5'b10111;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "H": case(row) 0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11111;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "I": case(row) 0:glyph_row=5'b01110;1:glyph_row=5'b00100;2:glyph_row=5'b00100;3:glyph_row=5'b00100;4:glyph_row=5'b00100;5:glyph_row=5'b00100;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "J": case(row) 0:glyph_row=5'b00111;1:glyph_row=5'b00010;2:glyph_row=5'b00010;3:glyph_row=5'b00010;4:glyph_row=5'b10010;5:glyph_row=5'b10010;6:glyph_row=5'b01100;default:glyph_row=0;endcase
                "K": case(row) 0:glyph_row=5'b10001;1:glyph_row=5'b10010;2:glyph_row=5'b10100;3:glyph_row=5'b11000;4:glyph_row=5'b10100;5:glyph_row=5'b10010;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "L": case(row) 0:glyph_row=5'b10000;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b10000;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b11111;default:glyph_row=0;endcase
                "M": case(row) 0:glyph_row=5'b10001;1:glyph_row=5'b11011;2:glyph_row=5'b10101;3:glyph_row=5'b10101;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "N": case(row) 0:glyph_row=5'b10001;1:glyph_row=5'b11001;2:glyph_row=5'b10101;3:glyph_row=5'b10011;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "O": case(row) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b10001;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "P": case(row) 0:glyph_row=5'b11110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11110;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b10000;default:glyph_row=0;endcase
                "Q": case(row) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b10001;4:glyph_row=5'b10101;5:glyph_row=5'b10010;6:glyph_row=5'b01101;default:glyph_row=0;endcase
                "R": case(row) 0:glyph_row=5'b11110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11110;4:glyph_row=5'b10100;5:glyph_row=5'b10010;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "S": case(row) 0:glyph_row=5'b01111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b01110;4:glyph_row=5'b00001;5:glyph_row=5'b00001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                "T": case(row) 0:glyph_row=5'b11111;1:glyph_row=5'b00100;2:glyph_row=5'b00100;3:glyph_row=5'b00100;4:glyph_row=5'b00100;5:glyph_row=5'b00100;6:glyph_row=5'b00100;default:glyph_row=0;endcase
                "U": case(row) 0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b10001;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "V": case(row) 0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b10001;4:glyph_row=5'b10001;5:glyph_row=5'b01010;6:glyph_row=5'b00100;default:glyph_row=0;endcase
                "W": case(row) 0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b10101;4:glyph_row=5'b10101;5:glyph_row=5'b10101;6:glyph_row=5'b01010;default:glyph_row=0;endcase
                "X": case(row) 0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b01010;3:glyph_row=5'b00100;4:glyph_row=5'b01010;5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "Y": case(row) 0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b01010;3:glyph_row=5'b00100;4:glyph_row=5'b00100;5:glyph_row=5'b00100;6:glyph_row=5'b00100;default:glyph_row=0;endcase
                "Z": case(row) 0:glyph_row=5'b11111;1:glyph_row=5'b00001;2:glyph_row=5'b00010;3:glyph_row=5'b00100;4:glyph_row=5'b01000;5:glyph_row=5'b10000;6:glyph_row=5'b11111;default:glyph_row=0;endcase
                ":": case(row) 1:glyph_row=5'b00100;2:glyph_row=5'b00100;4:glyph_row=5'b00100;5:glyph_row=5'b00100;default:glyph_row=0;endcase
                ".": case(row) 5:glyph_row=5'b00100;6:glyph_row=5'b00100;default:glyph_row=0;endcase
                ",": case(row) 5:glyph_row=5'b00100;6:glyph_row=5'b01000;default:glyph_row=0;endcase
                "!": case(row) 0:glyph_row=5'b00100;1:glyph_row=5'b00100;2:glyph_row=5'b00100;3:glyph_row=5'b00100;5:glyph_row=5'b00100;default:glyph_row=0;endcase
                "?": case(row) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b00010;3:glyph_row=5'b00100;5:glyph_row=5'b00100;default:glyph_row=0;endcase
                "-": case(row) 3:glyph_row=5'b11111;default:glyph_row=0;endcase
                "_": case(row) 6:glyph_row=5'b11111;default:glyph_row=0;endcase
                "/": case(row) 0:glyph_row=5'b00001;1:glyph_row=5'b00010;2:glyph_row=5'b00010;3:glyph_row=5'b00100;4:glyph_row=5'b01000;5:glyph_row=5'b01000;6:glyph_row=5'b10000;default:glyph_row=0;endcase
                default: glyph_row = extra_glyph_row(character,row);
            endcase
        end
    endfunction

    integer param_local_x;
    integer param_cell;
    integer param_col;
    // Production maximum: pixel_x 639 + scroll_pos 1215 = 1854.
    // Keep an extra bit for the full 10-bit X input during blanking.
    // Unsigned bounded arithmetic avoids a 32-bit signed /18 pixel path.
    reg [11:0] subtitle_stream_x;
    reg [6:0] subtitle_cell;
    reg [4:0] subtitle_col;
    reg [7:0] selected_char;
    reg [4:0] selected_row;
    reg [15:0] selected_chinese_row;
    reg param_pixel;
    wire [15:0] scene_row;
    wire [3:0] scene_row_index = line_y-SUBTITLE_Y-2;
    scene_chinese_font u_scene_font(.code(selected_char),.row(scene_row_index),.pixels(scene_row));
    reg subtitle_pixel;

    always @* begin
        param_local_x = pixel_x - PARAM_X;
        param_cell = 0;
        param_col = 0;
        subtitle_stream_x = pixel_x + scroll_pos;
        if (!subtitle_wrapped_x[12])
            subtitle_stream_x = subtitle_wrapped_x[11:0];
        subtitle_cell = 0;
        subtitle_col = 0;
        selected_char = " ";
        selected_row = 5'b00000;
        selected_chinese_row = 16'b0;
        param_pixel = 1'b0;
        subtitle_pixel = 1'b0;

        if (ENABLE_PARAMS && enable && de && pixel_x >= PARAM_X &&
            pixel_x < PARAM_X + PARAM_CHARS*CELL_W &&
            line_y >= PARAM_Y && line_y < PARAM_Y + CELL_H) begin
            param_cell = param_local_x / CELL_W;
            param_col = (param_local_x - param_cell*CELL_W) >> 1;
            if (param_col < 5 && ((line_y-PARAM_Y) >> 1) < 7) begin
                selected_char = param_char(param_cell);
                selected_row = glyph_row(selected_char, (line_y-PARAM_Y) >> 1);
                param_pixel = selected_row[4-param_col];
            end
        end

        if (enable && subtitle_enable_frame && de &&
            pixel_x >= 8 && pixel_x < H_ACTIVE-8 &&
            line_y >= SUBTITLE_Y && line_y < SUBTITLE_Y + SUBTITLE_CELL_H &&
            subtitle_stream_x < subtitle_width) begin
            subtitle_cell = subtitle_stream_x / 12'd18;
            subtitle_col = subtitle_stream_x - subtitle_cell*12'd18;
            selected_char = subtitle_char(subtitle_cell);
            if (selected_char[7]) begin
                if (subtitle_col >= 1 && subtitle_col < 17 &&
                    line_y >= SUBTITLE_Y+2 && line_y < SUBTITLE_Y+18) begin
                    selected_chinese_row = chinese_glyph_row(
                        selected_char[3:0], line_y-SUBTITLE_Y-2);
                    subtitle_pixel = (selected_char>=8'h90 && selected_char<=8'haf) ?
                        scene_row[16-subtitle_col] : selected_chinese_row[16-subtitle_col];
                end
            end else if (subtitle_col >= 4 && subtitle_col < 14 &&
                         line_y >= SUBTITLE_Y+2 && line_y < SUBTITLE_Y+16) begin
                selected_row = glyph_row(selected_char, (line_y-SUBTITLE_Y-2) >> 1);
                subtitle_pixel = selected_row[4-((subtitle_col-4) >> 1)];
            end
        end
    end

    assign overlay_active = param_pixel || subtitle_pixel;
    assign rgb_out = overlay_active ? 24'hff0000 : rgb_in;
endmodule
