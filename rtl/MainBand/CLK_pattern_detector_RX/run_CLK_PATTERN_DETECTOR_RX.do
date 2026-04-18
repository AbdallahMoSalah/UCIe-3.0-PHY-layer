vlib work
vlog CLK_PATTERN_DETECTOR_RX.sv CLK_PATTERN_DETECTOR_RX_tb.sv
vsim -voptargs=+acc work.CLK_PATTERN_DETECTOR_RX_tb
add wave *
run -all
add wave -position insertpoint  \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_toggle_p \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_toggle_n \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_toggle_track \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_zero_p \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_zero_n \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_zero_track \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_16_consecetive_p \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_16_consecetive_n \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_16_consecetive_track \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/clk_p_p_w \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/clk_p_n_w \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/clk_n_p_w \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/clk_n_n_w \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/track_p_w \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/track_n_w \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/flag_p_tog \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/flag_p_zero \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/flag_n_tog \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/flag_n_zero \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/flag_track_tog \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/flag_track_zero
#quit -sim