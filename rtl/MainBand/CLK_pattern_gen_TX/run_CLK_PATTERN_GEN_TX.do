vlib work
vlog CLK_PATTERN_GEN_TX.sv CLK_PATTERN_GEN_TX_tb.sv
vsim -voptargs=+acc work.CLK_PATTERN_GEN_TX_tb
add wave *
run -all
#quit -sim