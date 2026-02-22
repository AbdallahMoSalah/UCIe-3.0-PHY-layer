vlib work
vlog RDI_SM_pkg.sv GATING_block.sv testbench.sv
vsim -voptargs=+acc work.testbench
do wave.do
run -all
