`timescale 1ns/1ps
// SW2 is asynchronous. Change visibility only at a frame boundary after 20ms
// of stable input; sampling/audio continue even while the overlay is hidden.
module waveform_switch_control #(
    parameter integer DEBOUNCE_CYCLES = 500000
) (
    input wire clk, rst_n, switch_in, vsync,
    output reg visible
);
    localparam integer COUNT_BITS = DEBOUNCE_CYCLES <= 1 ? 1 : $clog2(DEBOUNCE_CYCLES);
    reg switch_meta, switch_sync, switch_stable, vs_q;
    reg [COUNT_BITS-1:0] count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            switch_meta <= 0;
            switch_sync <= 0;
            switch_stable <= 0;
            count <= 0;
            vs_q <= 1;
            visible <= 0;
        end else begin
            switch_meta <= switch_in;
            switch_sync <= switch_meta;
            vs_q <= vsync;
            if (switch_sync == switch_stable) count <= 0;
            else if (count == DEBOUNCE_CYCLES-1) begin
                switch_stable <= switch_sync;
                count <= 0;
            end else count <= count + 1'b1;
            if (vs_q && !vsync) visible <= switch_stable;
        end
    end
endmodule
