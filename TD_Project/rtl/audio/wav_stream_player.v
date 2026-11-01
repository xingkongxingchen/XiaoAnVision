`timescale 1ns/1ps

// R3'-A: stream real audio content from the TF card and feed it into the
// existing HDMI audio chain (docs/29 rev: "what actually wins"). This module
// sits between the SD sector-read infrastructure and the PCM sample
// interface, using a dual-port BRAM circular buffer to absorb the ~12.5x
// rate mismatch between TF reads (~1.2 MB/s burst) and audio consumption
// (96 KB/s at 48 kHz 16-bit mono).
//
// Architecture:
//   TF sector bytes (mem_clk domain, byte-serial)
//     -> pair into 16-bit samples -> write into BRAM circular buffer
//   Audio sample ticks (pixel_clk domain, ~48 kHz)
//     -> read from BRAM -> output on valid/ready PCM interface
//
// The write side uses a sector-level state machine: issue one sector read,
// fill 256 samples (512 bytes), then issue the next. The read side consumes
// at the audio sample rate. Pointer crossing uses gray-coded 2FF sync (the
// established idiom). Buffer underflow outputs silence (zeros) with
// sample_valid still asserted, so the downstream HDMI chain never stalls.
//
// Data format: raw 16-bit signed little-endian PCM, 48 kHz mono. The PC
// tool (tools/make_audio_corpus.py) converts any WAV to this format before
// writing to the TF card. Endianness: TF bytes arrive LSB first.
module wav_stream_player #(
    parameter integer ADDR_WIDTH = 12,         // 4096 x 16-bit = 8 KB
    parameter integer SAMPLES_PER_SECTOR = 256, // 512 bytes / 2
    parameter integer LOOP = 0
) (
    // write side: mem_clk domain (SD SPI engine clock)
    input  wire        wr_clk,
    input  wire        wr_rst_n,
    input  wire        play_enable,        // level: stream active
    input  wire [31:0] start_lba,          // first data sector (after WAV header)
    input  wire [31:0] total_sectors,      // audio data extent in sectors
    output wire        sd_req,             // request a sector read
    output wire [31:0] sd_lba,
    input  wire        sd_busy,
    input  wire        sd_valid,           // one byte per valid pulse
    input  wire [7:0]  sd_byte,
    input  wire [8:0]  sd_byte_index,      // 0..511 within sector
    input  wire        sd_done,
    input  wire [7:0]  sd_error,

    // read side: pixel_clk domain (audio chain clock)
    input  wire        rd_clk,
    input  wire        rd_rst_n,
    input  wire        sample_tick,        // ~48 kHz pulse: consume one sample
    output wire signed [15:0] sample_out,
    output reg         sample_valid,
    input  wire        sample_ready,       // from downstream (always 1 in our chain)

    // status (read side)
    output reg  [31:0] sample_counter,     // samples consumed (for OSD)
    output wire        stream_active,      // play_enable && not ended
    output wire        stream_end,         // all data consumed
    output wire        buffer_low,         // < 25% remaining (for OSD/status)
    output reg         underrun
);
    // ---------------- circular buffer ----------------
    reg [15:0] buffer [0:(1<<ADDR_WIDTH)-1];
    // Include a wrap bit: full and empty must not alias after one buffer lap.
    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;

    // write state sync to read domain (quasi-static, 2FF is safe)
    reg ended_sync1, ended_sync2, play_sync1, play_sync2;
    reg primed;

    // gray-coded sync: wr_ptr -> rd_clk domain
    reg [ADDR_WIDTH:0] wr_gray;
    reg [ADDR_WIDTH:0] wr_gray_sync1, wr_gray_sync2;
    // gray-coded sync: rd_ptr -> wr_clk domain
    reg [ADDR_WIDTH:0] rd_gray;
    reg [ADDR_WIDTH:0] rd_gray_sync1, rd_gray_sync2;

    function [ADDR_WIDTH:0] to_gray;
        input [ADDR_WIDTH:0] b;
        begin
            to_gray = b ^ (b >> 1);
        end
    endfunction

    function [ADDR_WIDTH:0] from_gray;
        input [ADDR_WIDTH:0] g;
        reg [ADDR_WIDTH:0] b;
        integer i;
        begin
            b[ADDR_WIDTH] = g[ADDR_WIDTH];
            for (i = ADDR_WIDTH-1; i >= 0; i = i - 1)
                b[i] = b[i+1] ^ g[i];
            from_gray = b;
        end
    endfunction

    // synchronized pointers (each in the other domain)
    wire [ADDR_WIDTH:0] wr_ptr_in_rd = from_gray(wr_gray_sync2);
    wire [ADDR_WIDTH:0] rd_ptr_in_wr = from_gray(rd_gray_sync2);

    // fill level in write domain (for flow control)
    wire [ADDR_WIDTH:0] level_wr = wr_ptr - rd_ptr_in_wr;
    // fill level in read domain (for buffer_low status)
    wire [ADDR_WIDTH:0] level_rd = wr_ptr_in_rd - rd_ptr;
    wire sector_room = level_wr <= (1 << ADDR_WIDTH) - SAMPLES_PER_SECTOR;

    // ---------------- write side state machine ----------------
    localparam [2:0] WS_IDLE  = 3'd0;
    localparam [2:0] WS_REQ   = 3'd1;
    localparam [2:0] WS_FILL  = 3'd2;
    localparam [2:0] WS_DONE  = 3'd3;
    localparam [2:0] WS_END   = 3'd4;
    reg [2:0]  wstate;
    // Compute capacity only while no writer can advance the write pointer.
    // Clear through FILL/IDLE/END so a completed burst cannot reuse old room.
    reg sector_room_q;
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) sector_room_q <= 1'b0;
        else sector_room_q <= (wstate == WS_REQ) && sector_room;
    end
    wire wstate_ended = (wstate == WS_END);
    reg [31:0] cur_lba;
    reg [31:0] sectors_read;
    reg [7:0]  lo_byte;             // little-endian pair assembly
    reg        lo_pending;
    reg [15:0] ram_sample;
    reg silence;
    wire sample_fetch=sample_tick && stream_active && (!sample_valid || sample_ready);
    // Synchronous, reset-free RAM ports are required for TD BRAM inference.
    always @(posedge wr_clk)
        if(wr_rst_n && wstate==WS_FILL && sd_valid && lo_pending)
            buffer[wr_ptr[ADDR_WIDTH-1:0]] <= {sd_byte,lo_byte};
    always @(posedge rd_clk)
        if(sample_fetch && primed && level_rd!=0)
            ram_sample <= buffer[rd_ptr[ADDR_WIDTH-1:0]];
    assign sample_out=silence ? 16'sd0 : ram_sample;

    // LBA must be stable BEFORE the cycle on which the adapter accepts req.
    assign sd_lba = cur_lba;
    assign sd_req = (wstate == WS_REQ) && play_enable && sector_room_q;
    // These outputs belong to rd_clk. Reading the last sector is not EOF until
    // the last buffered sample has also been accepted by the downstream mux.
    assign stream_end = play_sync2 && ended_sync2 && level_rd == 0 && !sample_valid;
    assign stream_active = play_sync2 && !stream_end;
    assign buffer_low = (level_rd < (1 << (ADDR_WIDTH-2))); // < 25%

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wstate         <= WS_IDLE;
            cur_lba        <= 32'd0;
            sectors_read   <= 32'd0;
            wr_ptr         <= {ADDR_WIDTH{1'b0}};
            lo_pending     <= 1'b0;
            lo_byte        <= 8'd0;
            rd_gray_sync1  <= {ADDR_WIDTH{1'b0}};
            rd_gray_sync2  <= {ADDR_WIDTH{1'b0}};
            wr_gray        <= 0;
        end else begin
            // gray-code sync of rd_ptr into wr domain
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;

            case (wstate)
            WS_IDLE: begin
                if (play_enable && start_lba != 32'd0 && total_sectors != 32'd0) begin
                    cur_lba      <= start_lba;
                    sectors_read <= 32'd0;
                    wr_ptr       <= {ADDR_WIDTH{1'b0}};
                    lo_pending   <= 1'b0;
                    wstate       <= WS_REQ;
                end
            end
            WS_REQ: begin
                if (sd_req && !sd_busy) begin
                    wstate  <= WS_FILL;
                end
            end
            WS_FILL: begin
                if (sd_valid) begin
                    if (!lo_pending) begin
                        lo_byte    <= sd_byte;
                        lo_pending <= 1'b1;
                    end else begin
                        wr_ptr         <= wr_ptr + 1'b1;
                        wr_gray        <= to_gray(wr_ptr + 1'b1);
                        lo_pending     <= 1'b0;
                    end
                end
                if (sd_done) begin
                    if (sd_error != 8'd0) begin
                        wstate <= WS_END;  // sector error: stop streaming
                    end else begin
                        sectors_read <= sectors_read + 1'b1;
                        cur_lba      <= cur_lba + 1'b1;
                        if (sectors_read + 1'b1 >= total_sectors) begin
                            if (LOOP) begin
                                // File owner restarts the FAT stream; retain both
                                // ring pointers so queued tail and new head join.
                                sectors_read <= 0;
                                cur_lba <= start_lba;
                                wstate <= WS_REQ;
                            end else wstate <= WS_END;
                        end
                        else
                            wstate <= WS_REQ;
                    end
                end
            end
            WS_DONE: wstate <= WS_REQ;  // unused, reserved
            WS_END: begin
                // stay ended until play_enable drops
                if (!play_enable)
                    wstate <= WS_IDLE;
            end
            default: wstate <= WS_IDLE;
            endcase

            // FAT lookup may fail between payload sectors, while WS_REQ is
            // waiting for its next credit. Retire there as well as WS_FILL.
            if (sd_done && sd_error != 0) wstate <= WS_END;

            // Reserve one whole sector before requesting it. Stop/restart in
            // this integration is coordinated by the common reset; do not
            // asynchronously discard an in-flight sector on play_enable.
        end
    end

    // ---------------- read side ----------------
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr         <= {ADDR_WIDTH{1'b0}};
            silence        <= 1'b1;
            sample_valid   <= 1'b0;
            sample_counter <= 32'd0;
            wr_gray_sync1  <= {ADDR_WIDTH{1'b0}};
            wr_gray_sync2  <= {ADDR_WIDTH{1'b0}};
            rd_gray        <= 0;
            ended_sync1 <= 0; ended_sync2 <= 0;
            play_sync1 <= 0; play_sync2 <= 0; primed <= 0;
            underrun <= 0;
        end else begin
            // gray-code sync of wr_ptr into rd domain
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
            ended_sync1 <= wstate_ended; ended_sync2 <= ended_sync1;
            play_sync1 <= play_enable; play_sync2 <= play_sync1;

            if (sample_valid && sample_ready) sample_valid <= 1'b0;
            if (level_rd >= SAMPLES_PER_SECTOR || ended_sync2) primed <= 1'b1;

            if (sample_fetch) begin
                if (primed && level_rd != 0) begin
                    // enough data (or stream ended with residual): play
                    silence      <= 1'b0;
                    rd_ptr       <= rd_ptr + 1'b1;
                    rd_gray      <= to_gray(rd_ptr + 1'b1);
                    sample_valid <= 1'b1;
                    sample_counter <= sample_counter + 1'b1;
                end else begin
                    if(LOOP && primed && !ended_sync2) underrun <= 1;
                    // prefill or underflow: silence, don't consume
                    silence      <= 1'b1;
                    sample_valid <= 1'b1;
                end
            end

            if (!play_sync2) begin
                rd_ptr         <= {ADDR_WIDTH{1'b0}};
                rd_gray <= 0; primed <= 0; sample_valid <= 0;
                sample_counter <= 32'd0;
            end
        end
    end
endmodule
