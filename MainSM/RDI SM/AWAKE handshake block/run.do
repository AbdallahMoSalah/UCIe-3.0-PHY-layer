vlib work
vlog AWAKE_handshake_block.sv testbench.sv
vsim -voptargs=+acc work.testbench
do wave.do
run -all