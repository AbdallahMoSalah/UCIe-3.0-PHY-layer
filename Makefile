# ===============================================
# UCIe PHY Simulation Makefile
# ===============================================

IS_UVM = $(filter run_uvm debug_uvm report_uvm clean,$(MAKECMDGOALS))

ifeq ($(IS_UVM),)

ifndef CONFIG
$(error CONFIG is not defined. Example: make run CONFIG=unit_rdi_packetizer TOP=RDI_Packetizer_tb)
endif

ifndef TOP
$(error TOP is not defined. Example: make run CONFIG=unit_rdi_packetizer TOP=RDI_Packetizer_tb)
endif

endif

MODE       ?= run
SEED       ?= default
SYNTH      ?= 0
REPORT_EXT ?= txt

# Non-UVM script
SIM_DO     = sim/scripts/run.do

# UVM Defaults & Script
UVM_CONFIG ?= ucie_phy_uvm
UVM_TOP    ?= ucie_tb_top
TEST       ?= ucie_happy_path_test
VERBOSITY  ?= UVM_LOW
SIM_UVM_DO = sim/scripts/run_uvm.do

.PHONY: run debug report ci clean run_uvm debug_uvm report_uvm

# -----------------------------------------------
# Run (console mode - standard TB)
# -----------------------------------------------
run:
	vsim -c -do "set CONFIG $(CONFIG); \
	             set TOP $(TOP); \
	             set MODE run; \
	             set SEED $(SEED); \
	             set SYNTH $(SYNTH); \
	             do $(SIM_DO)"

# -----------------------------------------------
# Debug (GUI mode - standard TB)
# -----------------------------------------------
debug:
	vsim -do "set CONFIG $(CONFIG); \
	          set TOP $(TOP); \
	          set MODE debug; \
	          set SEED $(SEED); \
	          set SYNTH $(SYNTH); \
	          do $(SIM_DO)"

# -----------------------------------------------
# Coverage Report (standard TB)
# -----------------------------------------------
report:
	vsim -c -do "set CONFIG $(CONFIG); \
	             set TOP $(TOP); \
	             set MODE report; \
				 set REPORT_EXT $(REPORT_EXT); \
	             set SEED $(SEED); \
	             set SYNTH $(SYNTH); \
	             do $(SIM_DO)"

# -----------------------------------------------
# CI Mode (standard TB)
# -----------------------------------------------
ci:
	vsim -c -do "set CONFIG $(CONFIG); \
	             set TOP $(TOP); \
	             set MODE ci; \
	             set SEED $(SEED); \
	             set SYNTH $(SYNTH); \
	             do $(SIM_DO)"

# ===============================================
# UVM Targets
# ===============================================

# -----------------------------------------------
# UVM Run (Console mode)
# Example: make run_uvm TEST=ucie_happy_path_test VERBOSITY=UVM_MEDIUM
# -----------------------------------------------
run_uvm:
	vsim -c -do "set CONFIG $(UVM_CONFIG); \
	             set TOP $(UVM_TOP); \
	             set TEST $(TEST); \
	             set VERBOSITY $(VERBOSITY); \
	             set MODE run; \
	             set SEED $(SEED); \
	             set SYNTH $(SYNTH); \
	             do $(SIM_UVM_DO)"

# -----------------------------------------------
# UVM Debug (GUI mode)
# Example: make debug_uvm TEST=ucie_asymmetric_width_test
# -----------------------------------------------
debug_uvm:
	vsim -do "set CONFIG $(UVM_CONFIG); \
	          set TOP $(UVM_TOP); \
	          set TEST $(TEST); \
	          set VERBOSITY $(VERBOSITY); \
	          set MODE debug; \
	          set SEED $(SEED); \
	          set SYNTH $(SYNTH); \
	          do $(SIM_UVM_DO)"

# -----------------------------------------------
# UVM Coverage Report
# Example: make report_uvm TEST=ucie_happy_path_test
# -----------------------------------------------
report_uvm:
	vsim -c -do "set CONFIG $(UVM_CONFIG); \
	             set TOP $(UVM_TOP); \
	             set TEST $(TEST); \
	             set VERBOSITY $(VERBOSITY); \
	             set MODE report; \
	             set REPORT_EXT $(REPORT_EXT); \
	             set SEED $(SEED); \
	             set SYNTH $(SYNTH); \
	             do $(SIM_UVM_DO)"

# -----------------------------------------------
# Clean Simulation Artifacts
# -----------------------------------------------
clean:
	@echo "Cleaning Questa artifacts..."
	rm -rf sim/work
	rm -rf sim/logs
	rm -f transcript
	rm -f vsim.wlf
	rm -f modelsim.ini
	rm -f *.vcd
	rm -rf work/