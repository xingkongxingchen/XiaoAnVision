`timescale 1ns/1ps

// Semantic wrapper around MiCu's dual-key event router.
// KEY1: short release -> next image.
// KEY2: short release -> auto-play toggle; long release -> previous image.
module slideshow_key_router #(
    parameter integer CLK_FREQ_HZ  = 100_000_000,
    parameter integer DEBOUNCE_MS  = 20,
    parameter integer LONG_PRESS_MS = 1000,
    parameter integer ENABLE_THUMBNAILS = 0,
    parameter integer ENABLE_PICTURE_MENU = 0
) (
    input  wire clk,
    input  wire rst_n,
    input  wire key_next_n,
    input  wire key_mode_n,
    output wire next_event,
    output wire auto_toggle_event,
    output wire prev_event,
    output wire thumbnail_toggle_event,
    output wire picture_menu_event
);
    localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam integer LONG_PRESS_CYCLES = (CLK_FREQ_HZ / 1000) * LONG_PRESS_MS;

    wire unused_save_event;
    wire unused_save_locked;
    wire unused_key_next_stable_n;
    wire unused_key_mode_stable_n;
    reg [2:0] rearm_count;
    // The original save guard is one-shot. Rearm only this key router after
    // both keys are released; the guard itself and the player are unchanged.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rearm_count <= 0;
        else if (rearm_count != 0) rearm_count <= rearm_count - 1'b1;
        else if (ENABLE_THUMBNAILS && unused_save_locked &&
                 unused_key_next_stable_n && unused_key_mode_stable_n)
            rearm_count <= 3'd4;
    end
    assign thumbnail_toggle_event = ENABLE_THUMBNAILS && unused_save_event;

    dual_key_chord_router #(
        .DEBOUNCE_CYCLES (DEBOUNCE_CYCLES),
        .HOLD_CYCLES     (LONG_PRESS_CYCLES),
        .KEY3_LONG_CYCLES(LONG_PRESS_CYCLES),
        .ENABLE_KEY2_LONG(ENABLE_PICTURE_MENU)
    ) u_router (
        .clk          (clk),
        .rst_n        (rst_n && rearm_count == 0),
        .save_enabled (ENABLE_THUMBNAILS != 0),
        .key2_n       (key_next_n),
        .key3_n       (key_mode_n),
        .key2_event   (next_event),
        .key2_long_event(picture_menu_event),
        .key3_event   (auto_toggle_event),
        .key3_long_event(prev_event),
        .save_event   (unused_save_event),
        .save_locked  (unused_save_locked),
        .key2_stable_n(unused_key_next_stable_n),
        .key3_stable_n(unused_key_mode_stable_n)
    );
endmodule
