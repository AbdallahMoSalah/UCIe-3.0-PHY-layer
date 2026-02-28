vlib work
vlog Demapper.sv Demapper_tb.sv
vsim -voptargs=+acc work.Demapper_tb
add wave *
run -all
#quit -sim