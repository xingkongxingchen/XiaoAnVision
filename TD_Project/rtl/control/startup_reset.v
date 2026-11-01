`timescale 1ns/1ps
// MiCu lecture 6 minimal startup sequence. Clocks/frequencies stay unchanged.
// PLL reset must depend ONLY on the physical reset, never on lock or init_done.
module startup_reset (
    input wire ref_clk, sd_clk, mem_clk, pixel_clk,
    input wire key_rst_n, sys_locked, video_locked, mem_init_done,
    output wire pll_reset,
    output wire ctrl_rst_n, sd_rst_n, mem_rst_n, pixel_rst_n,
    output wire loader_rst_n
);
    wire release_n = key_rst_n & sys_locked & video_locked;
    wire mem_ready_sd;
    assign pll_reset = ~key_rst_n;
    reset_sync u_ctrl (.clk(ref_clk), .ext_rst_n(release_n), .rst_n_sync(ctrl_rst_n));
    reset_sync u_sd (.clk(sd_clk), .ext_rst_n(release_n), .rst_n_sync(sd_rst_n));
    reset_sync u_mem (.clk(mem_clk), .ext_rst_n(release_n), .rst_n_sync(mem_rst_n));
    reset_sync u_pixel (.clk(pixel_clk), .ext_rst_n(release_n), .rst_n_sync(pixel_rst_n));
    sync_2ff u_mem_ready (.clk(sd_clk), .rst_n(sd_rst_n),
                         .async_in(mem_init_done), .sync_out(mem_ready_sd));
    // Keep card scanning/loading in reset until memory is initialized.
    // Memory itself is NOT gated by init_done: that would deadlock startup.
    reset_sync u_loader (.clk(sd_clk), .ext_rst_n(sd_rst_n & mem_ready_sd),
                         .rst_n_sync(loader_rst_n));
endmodule
