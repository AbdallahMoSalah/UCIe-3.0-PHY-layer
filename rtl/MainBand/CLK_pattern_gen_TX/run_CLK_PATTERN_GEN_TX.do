vlib work
vlog CLK_PATTERN_GEN_TX.sv phase_delay.sv CLK_PATTERN_GEN_TX_tb.sv
vsim -voptargs=+acc work.CLK_PATTERN_GEN_TX_tb
add wave *
run -all
#quit -sim
add wave -position insertpoint  \
sim:/CLK_PATTERN_GEN_TX_tb/dut/counter_toggle \
sim:/CLK_PATTERN_GEN_TX_tb/dut/counter_zero \
sim:/CLK_PATTERN_GEN_TX_tb/dut/counter_main