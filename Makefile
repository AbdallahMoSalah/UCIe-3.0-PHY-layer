# ===============================================
# UCIe PHY Simulation Makefile
# ===============================================

# -----------------------------------------------
# Require CONFIG and TOP except for clean
# -----------------------------------------------
ifneq ($(MAKECMDGOALS),clean)

ifndef CONFIG
$(error CONFIG is not defined. Example: make run CONFIG=unit_rdi_packetizer TOP=RDI_Packetizer_tb)
endif

ifndef TOP
$(error TOP is not defined. Example: make run CONFIG=unit_rdi_packetizer TOP=RDI_Packetizer_tb)
endif

endif

MODE   ?= run
SEED   ?= default
SYNTH  ?= 0
REPORT_EXT ?= txt
SIM_DO = sim/scripts/run.do

.PHONY: run debug report ci clean

# -----------------------------------------------
# Run (console mode)
# -----------------------------------------------
run:
	vsim -c -do "set CONFIG $(CONFIG); \
	             set TOP $(TOP); \
	             set MODE run; \
	             set SEED $(SEED); \
	             set SYNTH $(SYNTH); \
	             do $(SIM_DO)"

# -----------------------------------------------
# Debug (GUI mode)
# -----------------------------------------------
debug:
	vsim -do "set CONFIG $(CONFIG); \
	          set TOP $(TOP); \
	          set MODE debug; \
	          set SEED $(SEED); \
	          set SYNTH $(SYNTH); \
	          do $(SIM_DO)"

# -----------------------------------------------
# Coverage Report
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
# CI Mode
# -----------------------------------------------
ci:
	vsim -c -do "set CONFIG $(CONFIG); \
	             set TOP $(TOP); \
	             set MODE ci; \
	             set SEED $(SEED); \
	             set SYNTH $(SYNTH); \
	             do $(SIM_DO)"


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