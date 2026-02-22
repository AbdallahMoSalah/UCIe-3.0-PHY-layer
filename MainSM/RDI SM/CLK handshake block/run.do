vlib work
vlog CLK_handshake_block.sv testbench.sv
vsim -voptargs=+acc work.testbench
do wave.do
run -all
#