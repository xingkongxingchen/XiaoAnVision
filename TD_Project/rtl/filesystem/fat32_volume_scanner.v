`timescale 1ns/1ps

module fat32_volume_scanner #(
    parameter integer AUDIO_ONLY = 0,
    parameter integer DUAL_AUDIO = 0,
    parameter integer ENABLE_CLIP = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        scan_start,
    output wire        scan_busy,
    output reg         scan_done,
    output reg  [7:0]  fs_error,
    output reg  [31:0] partition_lba,
    output reg  [7:0]  sectors_per_cluster,
    output reg  [31:0] fat_start_lba,
    output reg  [31:0] data_start_lba,
    output reg  [31:0] max_cluster,
    output reg  [3:0]  resource_valid,
    output reg  [31:0] resource0_cluster,
    output reg  [31:0] resource1_cluster,
    output reg  [31:0] resource2_cluster,
    output reg  [31:0] resource3_cluster,
    output reg  [31:0] resource0_size,
    output reg  [31:0] resource1_size,
    output reg  [31:0] resource2_size,
    output reg  [31:0] resource3_size,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_busy,
    input  wire        sector_valid,
    input  wire [7:0]  sector_byte,
    input  wire [8:0]  sector_byte_index,
    input  wire        sector_done,
    input  wire [7:0]  sector_error
);

    localparam ERR_NONE            = 8'h00;
    localparam ERR_SECTOR          = 8'h10;
    localparam ERR_BOOT_SIGNATURE  = 8'h20;
    localparam ERR_UNSUPPORTED_BPB = 8'h21;
    localparam ERR_RESOURCE_MISSING= 8'h22;

    localparam ST_IDLE       = 4'd0;
    localparam ST_READ0_REQ  = 4'd1;
    localparam ST_READ0_WAIT = 4'd2;
    localparam ST_BOOT_PARSE = 4'd3;
    localparam ST_BOOT_REQ   = 4'd4;
    localparam ST_BOOT_WAIT  = 4'd5;
    localparam ST_ROOT_REQ   = 4'd6;
    localparam ST_ROOT_WAIT  = 4'd7;
    localparam ST_DIR_SCAN   = 4'd8;
    localparam ST_FINISH     = 4'd9;
    localparam ST_BOOT_LAYOUT= 4'd10;
    localparam ST_BOOT_ROOT  = 4'd11;
    localparam ST_ROOT_SHIFT = 4'd12;
    localparam ST_ROOT_ADD   = 4'd13;
    localparam ST_BOOT_CHECK = 4'd14;
    reg [32:0] layout_span, partition_end;
    reg layout_bad_fat;
    reg [31:0] root_bias, root_sectors;
    reg [31:0] cluster_count;
    reg [32:0] required_fat_entries;
    reg bpb_bad_geometry, bpb_bad_layout, bpb_bad_size, bpb_bad_flags;
    wire bpb_invalid=bpb_bad_geometry || bpb_bad_layout || bpb_bad_size || bpb_bad_flags;

    reg [3:0] state;
    reg [7:0] sector_buffer [0:511];
    reg [4:0] directory_entry_index;
    reg [31:0] root_cluster;
    reg [31:0] total_sectors;
    reg [31:0] fat_sectors;
    reg [7:0] fat_count;
    reg [15:0] reserved_sectors;
    reg [31:0] root_lba;
    reg [7:0] root_sector_index;
    reg directory_end;
    reg [31:0] data_sector_count;
    reg [31:0] fat_span;
    reg [2:0] sectors_per_cluster_shift;
    reg [7:0] dir_name0;
    reg [7:0] dir_name1;
    reg [7:0] dir_name2;
    reg [7:0] dir_name3;
    reg [7:0] dir_name4;
    reg [7:0] dir_name5;
    reg [7:0] dir_name6;
    reg [7:0] dir_name7;
    reg [7:0] dir_name8;
    reg [7:0] dir_name9;
    reg [7:0] dir_name10;
    reg       dir_entry_match;
    reg [1:0] dir_resource_index;
    reg [15:0] dir_cluster_high;
    reg [15:0] dir_cluster_low;
    reg [31:0] dir_file_size;
    reg dir_pic_prefix, dir_pic_suffix, dir_pic_number;
    reg dir_audio_prefix, dir_alert_prefix, dir_pcm_suffix, dir_attribute_ok;
    reg dir_clip_name;
    reg signature_low_ok, signature_high_ok;

    assign scan_busy = (state != ST_IDLE);

    function [15:0] le16;
        input integer offset;
        begin
            le16 = {sector_buffer[offset+1], sector_buffer[offset]};
        end
    endfunction

    function [31:0] le32;
        input integer offset;
        begin
            le32 = {sector_buffer[offset+3], sector_buffer[offset+2],
                    sector_buffer[offset+1], sector_buffer[offset]};
        end
    endfunction

    function valid_spc;
        input [7:0] value;
        begin
            valid_spc = value != 0 && ((value & (value - 1'b1)) == 0);
        end
    endfunction

    function [2:0] spc_shift;
        input [7:0] value;
        begin
            case (value)
                8'd2:   spc_shift = 3'd1;
                8'd4:   spc_shift = 3'd2;
                8'd8:   spc_shift = 3'd3;
                8'd16:  spc_shift = 3'd4;
                8'd32:  spc_shift = 3'd5;
                8'd64:  spc_shift = 3'd6;
                8'd128: spc_shift = 3'd7;
                default: spc_shift = 3'd0;
            endcase
        end
    endfunction

    function [1:0] matching_resource;
        input integer base;
        begin
            if (sector_buffer[base+0] == "P" && sector_buffer[base+1] == "I" &&
                sector_buffer[base+2] == "C" && sector_buffer[base+3] == "1" &&
                sector_buffer[base+8] == "B" && sector_buffer[base+9] == "M" &&
                sector_buffer[base+10] == "P")
                matching_resource = 2'd0;
            else if (sector_buffer[base+0] == "P" && sector_buffer[base+1] == "I" &&
                     sector_buffer[base+2] == "C" && sector_buffer[base+3] == "2" &&
                     sector_buffer[base+8] == "B" && sector_buffer[base+9] == "M" &&
                     sector_buffer[base+10] == "P")
                matching_resource = 2'd1;
            else if (sector_buffer[base+0] == "P" && sector_buffer[base+1] == "I" &&
                     sector_buffer[base+2] == "C" && sector_buffer[base+3] == "3" &&
                     sector_buffer[base+8] == "B" && sector_buffer[base+9] == "M" &&
                     sector_buffer[base+10] == "P")
                matching_resource = 2'd2;
            else
                matching_resource = 2'd3;
        end
    endfunction

    task finish_with_error;
        input [7:0] code;
        begin
            fs_error <= code;
            state <= ST_FINISH;
        end
    endtask

    task accept_directory_entry;
        input integer base;
        reg [1:0] resource_index;
        reg [31:0] first_cluster;
        reg [31:0] file_size;
        begin
            resource_index = matching_resource(base);
            first_cluster = {sector_buffer[base+21], sector_buffer[base+20],
                             sector_buffer[base+27], sector_buffer[base+26]};
            file_size = le32(base+28);
            case (resource_index)
                2'd0: begin
                    resource0_cluster <= first_cluster;
                    resource0_size <= file_size;
                    resource_valid[0] <= 1'b1;
                end
                2'd1: begin
                    resource1_cluster <= first_cluster;
                    resource1_size <= file_size;
                    resource_valid[1] <= 1'b1;
                end
                2'd2: begin
                    resource2_cluster <= first_cluster;
                    resource2_size <= file_size;
                    resource_valid[2] <= 1'b1;
                end
                default: begin
                    resource3_cluster <= first_cluster;
                    resource3_size <= file_size;
                    resource_valid[3] <= 1'b1;
                end
            endcase
        end
    endtask

    // Buffer has no reset content. Keeping its write port outside the reset
    // state machine avoids a high-fanout reset-to-write-enable timing path.
    // BPB fields are all below byte 48, so these checks settle before sector_done.
    // Sample each signature byte on its arrival. This is also valid when
    // the transport ends with byte 511, unlike a lagging buffer comparison.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin signature_low_ok<=0; signature_high_ok<=0; end
        else if (sector_valid && state != ST_ROOT_WAIT) begin
            if (sector_byte_index==510) signature_low_ok<=sector_byte==8'h55;
            if (sector_byte_index==511) signature_high_ok<=sector_byte==8'haa;
        end
    end
    always @(posedge clk) begin
        // Names are complete at byte 10. Grouped comparisons settle at byte
        // 11 and are consumed at byte 12, before metadata is accepted at 31.
        dir_pic_prefix <= {dir_name0,dir_name1,dir_name2} == "PIC";
        dir_pic_suffix <= {dir_name4,dir_name5,dir_name6,dir_name7,
                           dir_name8,dir_name9,dir_name10} == "    BMP";
        dir_pic_number <= dir_name3 >= "1" && dir_name3 <= "4";
        dir_clip_name <= {dir_name0,dir_name1,dir_name2,dir_name3,dir_name4,dir_name5,dir_name6,dir_name7,dir_name8,dir_name9,dir_name10} == "CLIP    BIN";
        dir_audio_prefix <= {dir_name0,dir_name1,dir_name2,dir_name3,dir_name4} == "AUDIO";
        dir_alert_prefix <= {dir_name0,dir_name1,dir_name2,dir_name3,dir_name4} == "ALERT";
        dir_pcm_suffix <= {dir_name5,dir_name6,dir_name7,dir_name8,dir_name9,dir_name10} == "   PCM";
        if (sector_valid && state != ST_ROOT_WAIT)
            sector_buffer[sector_byte_index] <= sector_byte;
        bpb_bad_geometry <= le16(11)!=512 || !valid_spc(sector_buffer[13]);
        bpb_bad_layout <= le16(14)==0 || (sector_buffer[16]!=1 && sector_buffer[16]!=2) ||
                          le16(17)!=0 || le16(22)!=0;
        bpb_bad_size <= le32(32)==0 || le32(36)==0 || le32(44)<2;
        bpb_bad_flags <= le16(42)!=0 ||
                         ((le16(40)&16'h0080)!=0 && (le16(40)&16'h000f)!=0);
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            scan_done <= 1'b0;
            fs_error <= ERR_NONE;
            partition_lba <= 32'd0;
            sectors_per_cluster <= 8'd0;
            fat_start_lba <= 32'd0;
            data_start_lba <= 32'd0;
            max_cluster <= 32'd0;
            resource_valid <= 4'd0;
            resource0_cluster <= 32'd0;
            resource1_cluster <= 32'd0;
            resource2_cluster <= 32'd0;
            resource3_cluster <= 32'd0;
            resource0_size <= 32'd0;
            resource1_size <= 32'd0;
            resource2_size <= 32'd0;
            resource3_size <= 32'd0;
            sector_req <= 1'b0;
            sector_lba <= 32'd0;
            directory_entry_index <= 5'd0;
            root_cluster <= 32'd0;
            total_sectors <= 32'd0;
            fat_sectors <= 32'd0;
            fat_count <= 8'd0;
            reserved_sectors <= 16'd0;
            root_lba <= 32'd0;
            root_bias <= 0; root_sectors <= 0;
            cluster_count <= 0; required_fat_entries <= 0;
            root_sector_index <= 0;
            directory_end <= 0;
            data_sector_count <= 32'd0;
            fat_span <= 32'd0;
            sectors_per_cluster_shift <= 3'd0;
            dir_name0 <= 8'd0;
            dir_name1 <= 8'd0;
            dir_name2 <= 8'd0;
            dir_name3 <= 8'd0;
            dir_name4 <= 8'd0;
            dir_name5 <= 8'd0;
            dir_name6 <= 8'd0;
            dir_name7 <= 8'd0;
            dir_name8 <= 8'd0;
            dir_name9 <= 8'd0;
            dir_name10 <= 8'd0;
            dir_entry_match <= 1'b0;
            dir_resource_index <= 2'd3;
            dir_cluster_high <= 16'd0;
            dir_cluster_low <= 16'd0;
            dir_file_size <= 32'd0;
            dir_attribute_ok <= 0;
            layout_span <= 0; partition_end <= 0; layout_bad_fat <= 0;
        end else begin
            scan_done <= 1'b0;
            sector_req <= 1'b0;

            if (sector_valid && state == ST_ROOT_WAIT) begin
                case (sector_byte_index[4:0])
                    5'd0: begin
                        dir_name0 <= sector_byte;
                        dir_entry_match <= 1'b0;
                        if (sector_byte == 0) directory_end <= 1'b1;
                    end
                    5'd1:  dir_name1 <= sector_byte;
                    5'd2:  dir_name2 <= sector_byte;
                    5'd3:  dir_name3 <= sector_byte;
                    5'd4:  dir_name4 <= sector_byte;
                    5'd5:  dir_name5 <= sector_byte;
                    5'd6:  dir_name6 <= sector_byte;
                    5'd7:  dir_name7 <= sector_byte;
                    5'd8:  dir_name8 <= sector_byte;
                    5'd9:  dir_name9 <= sector_byte;
                    5'd10: dir_name10 <= sector_byte;
                    5'd11: begin
                        dir_attribute_ok <= !directory_end && (sector_byte & 8'h18) == 0;
                    end
                    5'd12: begin
                        if (AUDIO_ONLY && dir_attribute_ok && dir_audio_prefix && dir_pcm_suffix) begin
                            dir_entry_match <= 1'b1;
                            dir_resource_index <= 2'd0;
                        end else if (AUDIO_ONLY && DUAL_AUDIO && dir_attribute_ok && dir_alert_prefix && dir_pcm_suffix) begin
                            dir_entry_match <= 1'b1;
                            dir_resource_index <= 2'd1;
                        end else if (AUDIO_ONLY && ENABLE_CLIP && dir_attribute_ok && dir_clip_name) begin
                            dir_entry_match <= 1'b1;
                            dir_resource_index <= 2'd2;
                        end else if (!AUDIO_ONLY && dir_attribute_ok && dir_pic_prefix && dir_pic_suffix && dir_pic_number) begin
                            dir_entry_match <= 1'b1;
                            dir_resource_index <= dir_name3 - "1";
                        end
                    end
                    5'd20: dir_cluster_high[7:0] <= sector_byte;
                    5'd21: dir_cluster_high[15:8] <= sector_byte;
                    5'd26: dir_cluster_low[7:0] <= sector_byte;
                    5'd27: dir_cluster_low[15:8] <= sector_byte;
                    5'd28: dir_file_size[7:0] <= sector_byte;
                    5'd29: dir_file_size[15:8] <= sector_byte;
                    5'd30: dir_file_size[23:16] <= sector_byte;
                    5'd31: begin
                        dir_file_size[31:24] <= sector_byte;
                        if (dir_entry_match) begin
                            case (dir_resource_index)
                                2'd0: begin
                                    resource0_cluster <= {dir_cluster_high, dir_cluster_low};
                                    resource0_size <= {sector_byte, dir_file_size[23:0]};
                                    resource_valid[0] <= 1'b1;
                                end
                                2'd1: begin
                                    resource1_cluster <= {dir_cluster_high, dir_cluster_low};
                                    resource1_size <= {sector_byte, dir_file_size[23:0]};
                                    resource_valid[1] <= 1'b1;
                                end
                                2'd2: begin
                                    resource2_cluster <= {dir_cluster_high, dir_cluster_low};
                                    resource2_size <= {sector_byte, dir_file_size[23:0]};
                                    resource_valid[2] <= 1'b1;
                                end
                                default: begin
                                    resource3_cluster <= {dir_cluster_high, dir_cluster_low};
                                    resource3_size <= {sector_byte, dir_file_size[23:0]};
                                    resource_valid[3] <= 1'b1;
                                end
                            endcase
                        end
                    end
                    default: begin end
                endcase
            end

            case (state)
                ST_IDLE: if (scan_start) begin
                    fs_error <= ERR_NONE;
                    partition_lba <= 32'd0;
                    resource_valid <= 4'd0;
                    directory_end <= 0;
                    root_sector_index <= 0;
                    state <= ST_READ0_REQ;
                end
                ST_READ0_REQ: if (!sector_busy) begin
                    sector_lba <= 32'd0;
                    sector_req <= 1'b1;
                    state <= ST_READ0_WAIT;
                end
                ST_READ0_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else if (!signature_low_ok || !signature_high_ok)
                        finish_with_error(ERR_BOOT_SIGNATURE);
                    else if (sector_buffer[0] == 8'heb || sector_buffer[0] == 8'he9) begin
                        partition_lba <= 32'd0;
                        state <= ST_BOOT_PARSE;
                    end else if (sector_buffer[450] == 8'h0b || sector_buffer[450] == 8'h0c) begin
                        partition_lba <= le32(454);
                        sector_lba <= le32(454);
                        state <= ST_BOOT_REQ;
                    end else begin
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    end
                end
                ST_BOOT_REQ: if (!sector_busy) begin
                    sector_req <= 1'b1;
                    state <= ST_BOOT_WAIT;
                end
                ST_BOOT_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else if (!signature_low_ok || !signature_high_ok)
                        finish_with_error(ERR_BOOT_SIGNATURE);
                    else
                        state <= ST_BOOT_PARSE;
                end
                ST_BOOT_PARSE: begin
                    if (bpb_invalid) begin
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    end else begin
                        sectors_per_cluster <= sector_buffer[13];
                        reserved_sectors <= le16(14);
                        fat_count <= sector_buffer[16];
                        total_sectors <= le32(32);
                        fat_sectors <= le32(36);
                        root_cluster <= le32(44);
                        sectors_per_cluster_shift <= spc_shift(sector_buffer[13]);
                        fat_span <= sector_buffer[16] == 2 ? (le32(36) << 1) : le32(36);
                        fat_start_lba <= partition_lba + le16(14);
                        state <= ST_BOOT_LAYOUT;
                    end
                end
                ST_BOOT_LAYOUT: begin
                    // Register the wide sums before range/error decoding.
                    layout_span <= {1'b0,fat_span}+reserved_sectors;
                    partition_end <= {1'b0,partition_lba}+total_sectors;
                    layout_bad_fat <= fat_count==2 && fat_sectors[31];
                    state <= ST_BOOT_CHECK;
                end
                ST_BOOT_CHECK: begin
                    if (layout_bad_fat || layout_span >= {1'b0,total_sectors} ||
                        partition_end > 33'h100000000)
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    else begin
                        data_start_lba <= fat_start_lba + fat_span;
                        data_sector_count <= total_sectors - layout_span[31:0];
                        state <= ST_BOOT_ROOT;
                    end
                end
                ST_BOOT_ROOT: begin
                    cluster_count <= data_sector_count >> sectors_per_cluster_shift;
                    root_bias <= root_cluster-2;
                    state <= ST_ROOT_SHIFT;
                end
                ST_ROOT_SHIFT: begin
                    root_sectors <= root_bias << sectors_per_cluster_shift;
                    max_cluster <= cluster_count+1'b1;
                    required_fat_entries <= {1'b0,cluster_count}+2;
                    state <= ST_ROOT_ADD;
                end
                ST_ROOT_ADD: begin
                    root_lba <= data_start_lba+root_sectors;
                    sector_lba <= data_start_lba+root_sectors;
                    if (root_cluster > max_cluster ||
                        required_fat_entries > ({8'd0,fat_sectors} << 7))
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    else state <= ST_ROOT_REQ;
                end
                ST_ROOT_REQ: if (!sector_busy) begin
                    dir_entry_match <= 1'b0;
                    sector_req <= 1'b1;
                    state <= ST_ROOT_WAIT;
                end
                ST_ROOT_WAIT: if (sector_done) begin
                    if (sector_error != 0)
                        finish_with_error(ERR_SECTOR);
                    else begin
                        directory_entry_index <= 5'd0;
                        state <= ST_DIR_SCAN;
                    end
                end
                ST_DIR_SCAN: begin
                    if (AUDIO_ONLY ? (ENABLE_CLIP ? &resource_valid[2:0] : (DUAL_AUDIO ? &resource_valid[1:0] : resource_valid[0])) : resource_valid == 4'hf)
                        state <= ST_FINISH;
                    else if (!directory_end && root_sector_index+1'b1 < sectors_per_cluster) begin
                        root_sector_index <= root_sector_index+1'b1;
                        sector_lba <= sector_lba+1'b1;
                        state <= ST_ROOT_REQ;
                    end
                    else
                        finish_with_error(ERR_RESOURCE_MISSING);
                end
                ST_FINISH: begin
                    scan_done <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
