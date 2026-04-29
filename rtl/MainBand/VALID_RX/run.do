vlib work
vlog Valid_RX.sv CLK_PATTERN_GEN_TX_tb.sv
vsim -voptargs=+acc work.CLK_PATTERN_GEN_TX_tb
add wave *
run -all
#quit -sim