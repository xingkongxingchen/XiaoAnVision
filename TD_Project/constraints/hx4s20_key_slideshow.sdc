create_clock -name clk_50m -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]

# PLL-derived clocks used by the media pipeline.
create_generated_clock -name sd_card_clk \
    -source [get_ports {clk}] -master_clock clk_50m \
    -multiply_by 2 [get_nets {sd_card_clk}]
create_generated_clock -name ext_mem_clk \
    -source [get_ports {clk}] -master_clock clk_50m \
    -multiply_by 2 -phase 0 [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
create_generated_clock -name ext_mem_clk_sft \
    -source [get_ports {clk}] -master_clock clk_50m \
    -multiply_by 2 -phase 180 [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
create_generated_clock -name video_clk \
    -source [get_ports {clk}] -master_clock clk_50m \
    -divide_by 2 [get_nets {video_clk}]
create_generated_clock -name hdmi_5x_clk \
    -source [get_ports {clk}] -master_clock clk_50m \
    -multiply_by 2.5 [get_nets {hdmi_5x_clk}]

# Preserve the existing clock-domain boundaries; audio now uses video_clk.
set_clock_groups -asynchronous \
    -group [get_clocks {clk_50m}] \
    -group [get_clocks {sd_card_clk}] \
    -group [get_clocks {ext_mem_clk ext_mem_clk_sft}] \
    -group [get_clocks {video_clk hdmi_5x_clk}]

# The shifted SDRAM clock only drives the embedded SDRAM hard-IP sampling
# interface. It is not a fabric data-transfer clock relative to ext_mem_clk.
set_false_path -from [get_clocks {ext_mem_clk}] -to [get_clocks {ext_mem_clk_sft}]
set_false_path -from [get_clocks {ext_mem_clk_sft}] -to [get_clocks {ext_mem_clk}]

# Asynchronous external reset and push-buttons are synchronized in RTL.
set_false_path -from [get_ports {rst_n}]
set_false_path -from [get_ports {key1 key2 key3}]
# UART input is asynchronous and feeds ONLY u_subtitle_uart/u_rx/rx_meta.
# The rx_meta -> rx_sync path and all subsequent logic remain clock-timed.
set_false_path -from [get_ports {uart_rx}]
# PC UART pad feeds only the first metastability register of its copied RX engine.
set_false_path -from [get_ports {pc_uart_rx}]
# SW4 feeds ONLY u_subtitle_uart/u_emergency/switch_meta. The following
# synchronizer stages and the debounce counter remain clock-timed.
set_false_path -from [get_ports {emergency_switch}]
# SW3 drives ONLY u_period_control/switch_sync[0]; downstream stages are timed.
set_false_path -from [get_ports {period_switch}]
# SW2 drives ONLY u_waveform_switch/switch_meta; downstream stages are timed.
set_false_path -from [get_ports {waveform_switch}]

# Bound each implemented serializer-to-pad path. This is a digital delay
# constraint; it does not replace an HDMI eye-diagram measurement.
set_max_delay -from [get_clocks {hdmi_5x_clk}] \
    -to [get_ports {HDMI_CLK_P HDMI_D0_P HDMI_D1_P HDMI_D2_P}] \
    8.000 -datapath_only

set_clock_uncertainty -hold 0.050 \
    [get_clocks {clk_50m sd_card_clk ext_mem_clk ext_mem_clk_sft video_clk hdmi_5x_clk}]

# SW1 pad feeds only u_video/g_clip/u_clip_control/sw_meta.
set_false_path -from [get_ports {clip_switch}]
