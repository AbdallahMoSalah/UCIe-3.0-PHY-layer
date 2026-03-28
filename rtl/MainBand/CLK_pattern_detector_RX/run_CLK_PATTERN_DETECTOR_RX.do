vlib work
vlog CLK_PATTERN_DETECTOR_RX.sv CLK_PATTERN_DETECTOR_RX_tb.sv
vsim -voptargs=+acc work.CLK_PATTERN_DETECTOR_RX_tb
add wave *
run -all
add wave -position insertpoint  \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_p \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_n \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_zero \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_16_consecetive \
sim:/CLK_PATTERN_DETECTOR_RX_tb/dut/counter_main
#quit -sim