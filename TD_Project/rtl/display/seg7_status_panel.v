`timescale 1ns/1ps

// HX4S20 board display driver.
// Both segments and SEL are active-low at the FPGA pins. Board figure 2-15
// shows PNP digit drivers; the manual's high-active SEL prose is misleading.
// SEL0 is the leftmost digit and SEL7 is the rightmost digit.
module seg7_status_panel #(
    parameter integer SCAN_STEP_CYCLES = 8192,
    parameter integer TRACE_PAGE_CYCLES = 100_000_000,
    parameter integer ENABLE_CRC_DIAG = 0
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       display_valid,
    input  wire [1:0] image_index,
    input  wire       auto_play_en,
    input  wire [3:0] loader_state,
    input  wire [2:0] image_count,
    input  wire       load_busy,
    input  wire       trace_captured,
    input  wire [31:0] trace_page0, trace_page1, trace_page2,
    input  wire [31:0] diag_summary,
    output reg  [7:0] seg_sel,
    output reg  [7:0] seg_data
);
    localparam integer SCAN_BITS = (SCAN_STEP_CYCLES <= 2) ? 1 : $clog2(SCAN_STEP_CYCLES);
    localparam [4:0] F_BLANK = 5'h10;
    localparam [4:0] F_P     = 5'h11;
    localparam [4:0] F_I     = 5'h12;
    localparam [4:0] F_C     = 5'h13;
    localparam [4:0] F_A     = 5'h14;
    localparam [4:0] F_S     = 5'h15;
    localparam [4:0] F_N     = 5'h16;
    localparam [4:0] F_DASH  = 5'h17;

    reg [SCAN_BITS-1:0] scan_count;
    reg [2:0] scan_index;
    reg [4:0] symbols [0:7];
    integer d;
    reg [2:0] trace_sync;
    reg trace_latched;
    reg [31:0] saved0,saved1,saved2;
    reg [26:0] page_count;
    reg [1:0] page_index;
    wire [31:0] trace_word = page_index==0 ? saved0 : page_index==1 ? saved1 : saved2;

    // The capture bus stays constant until reset; sample only after its flag
    // has crossed three display-clock stages.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            trace_sync<=0;trace_latched<=0;saved0<=0;saved1<=0;saved2<=0;
            page_count<=0;page_index<=0;
        end else begin
            trace_sync<={trace_sync[1:0],trace_captured};
            if(trace_sync[2] && !trace_latched) begin
                saved0<=trace_page0;saved1<=trace_page1;saved2<=trace_page2;
                trace_latched<=1'b1;
            end
            if(trace_latched) begin
                if(page_count==TRACE_PAGE_CYCLES-1) begin
                    page_count<=0;page_index<=page_index==2 ? 0 : page_index+1'b1;
                end else page_count<=page_count+1'b1;
            end
        end
    end

    function [6:0] seg_font;
        input [4:0] sym;
        begin
            case (sym)
                5'd0: seg_font = 7'h3f;
                5'd1: seg_font = 7'h06;
                5'd2: seg_font = 7'h5b;
                5'd3: seg_font = 7'h4f;
                5'd4: seg_font = 7'h66;
                5'd5: seg_font = 7'h6d;
                5'd6: seg_font = 7'h7d;
                5'd7: seg_font = 7'h07;
                5'd8: seg_font = 7'h7f;
                5'd9: seg_font = 7'h6f;
                5'd10: seg_font = 7'h77;
                5'd11: seg_font = 7'h7c;
                5'd12: seg_font = 7'h39;
                5'd13: seg_font = 7'h5e;
                5'd14: seg_font = 7'h79;
                5'd15: seg_font = 7'h71;
                F_BLANK: seg_font = 7'h00;
                F_P:     seg_font = 7'h73;
                F_I:     seg_font = 7'h06;
                F_C:     seg_font = 7'h39;
                F_A:     seg_font = 7'h77;
                F_S:     seg_font = 7'h6d;
                F_N:     seg_font = 7'h54;
                F_DASH:  seg_font = 7'h40;
                default: seg_font = 7'h00;
            endcase
        end
    endfunction

    always @* begin
        for (d = 0; d < 8; d = d + 1)
            symbols[d] = F_BLANK;

        // P1n4b4A1: committed image, count, busy/parser state, auto flag.
        // S0 means no committed image. '-' in place of b means not busy.
        symbols[0] = display_valid ? F_P : F_S;
        symbols[1] = display_valid ? ({3'b000, image_index} + 5'd1) : 5'd0;
        symbols[2] = F_N;
        symbols[3] = {2'b00, image_count};
        symbols[4] = load_busy ? 5'd11 : F_DASH;
        symbols[5] = {1'b0, loader_state};
        symbols[6] = F_A;
        symbols[7] = {4'b0000, auto_play_en};
        if(ENABLE_CRC_DIAG && display_valid)
            for(d=0;d<8;d=d+1)
                symbols[d]={1'b0,diag_summary[(7-d)*4 +: 4]};
        if(trace_latched)
            for(d=0;d<8;d=d+1)
                symbols[d]={1'b0,trace_word[(7-d)*4 +: 4]};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_count <= {SCAN_BITS{1'b0}};
            scan_index <= 3'd0;
            seg_sel    <= 8'hff;
            seg_data   <= 8'hff;
        end else begin
            if (scan_count == SCAN_STEP_CYCLES - 1) begin
                scan_count <= {SCAN_BITS{1'b0}};
                scan_index <= scan_index + 1'b1;
            end else begin
                scan_count <= scan_count + 1'b1;
            end
            seg_sel  <= ~(8'b0000_0001 << scan_index);
            seg_data <= {1'b1, ~seg_font(symbols[scan_index])};
        end
    end
endmodule
