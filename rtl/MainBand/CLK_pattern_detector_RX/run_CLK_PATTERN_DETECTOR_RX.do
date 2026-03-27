vlib work
vlog CLK_PATTERN_DETECTOR_RX.sv CLK_PATTERN_DETECTOR_RX_tb.sv
vsim -voptargs=+acc work.CLK_PATTERN_DETECTOR_RX_tb
add wave *
run -all
add wave -position insertpoint  \
sim:/CLK_PATTERN_DETECTOR_RX_tb/uut/counter_toggle \
sim:/CLK_PATTERN_DETECTOR_RX_tb/uut/counter_zero \
sim:/CLK_PATTERN_DETECTOR_RX_tb/uut/counter_main \
sim:/CLK_PATTERN_DETECTOR_RX_tb/uut/clk_p_d
#quit -sim