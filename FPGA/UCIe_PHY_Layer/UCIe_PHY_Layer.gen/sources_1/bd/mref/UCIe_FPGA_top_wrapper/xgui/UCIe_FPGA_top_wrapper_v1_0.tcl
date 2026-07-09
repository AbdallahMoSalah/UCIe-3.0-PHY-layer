# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "ADVANCED_PKG_CAP" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CLK_FRQ_HZ" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CLK_MODE_CAP" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CLK_PHASE_CAP" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DATA_WIDTH_MB" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DATA_WIDTH_SB" -parent ${Page_0}
  ipgui::add_param $IPINST -name "GAP_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "L2SPD_CAP" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MAX_LINK_SPEED_CAP" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MAX_LINK_WIDTH_CAP" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MB_RX_FIFO_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MODULE_ID" -parent ${Page_0}
  ipgui::add_param $IPINST -name "NUM_LANES" -parent ${Page_0}
  ipgui::add_param $IPINST -name "N_BYTES" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PLL_PERIOD_NS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PMO_CAP" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PSPT_CAP" -parent ${Page_0}
  ipgui::add_param $IPINST -name "RX_ALIGN_DELAY" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SB_RX_FIFO_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SB_TX_DN_CRD_INIT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SPMW_CAP" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SUPPORTEDVSWING_CAP" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TARR_CAP" -parent ${Page_0}
  ipgui::add_param $IPINST -name "VALID_PATTERN" -parent ${Page_0}


}

proc update_PARAM_VALUE.ADVANCED_PKG_CAP { PARAM_VALUE.ADVANCED_PKG_CAP } {
	# Procedure called to update ADVANCED_PKG_CAP when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ADVANCED_PKG_CAP { PARAM_VALUE.ADVANCED_PKG_CAP } {
	# Procedure called to validate ADVANCED_PKG_CAP
	return true
}

proc update_PARAM_VALUE.CLK_FRQ_HZ { PARAM_VALUE.CLK_FRQ_HZ } {
	# Procedure called to update CLK_FRQ_HZ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CLK_FRQ_HZ { PARAM_VALUE.CLK_FRQ_HZ } {
	# Procedure called to validate CLK_FRQ_HZ
	return true
}

proc update_PARAM_VALUE.CLK_MODE_CAP { PARAM_VALUE.CLK_MODE_CAP } {
	# Procedure called to update CLK_MODE_CAP when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CLK_MODE_CAP { PARAM_VALUE.CLK_MODE_CAP } {
	# Procedure called to validate CLK_MODE_CAP
	return true
}

proc update_PARAM_VALUE.CLK_PHASE_CAP { PARAM_VALUE.CLK_PHASE_CAP } {
	# Procedure called to update CLK_PHASE_CAP when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CLK_PHASE_CAP { PARAM_VALUE.CLK_PHASE_CAP } {
	# Procedure called to validate CLK_PHASE_CAP
	return true
}

proc update_PARAM_VALUE.DATA_WIDTH_MB { PARAM_VALUE.DATA_WIDTH_MB } {
	# Procedure called to update DATA_WIDTH_MB when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DATA_WIDTH_MB { PARAM_VALUE.DATA_WIDTH_MB } {
	# Procedure called to validate DATA_WIDTH_MB
	return true
}

proc update_PARAM_VALUE.DATA_WIDTH_SB { PARAM_VALUE.DATA_WIDTH_SB } {
	# Procedure called to update DATA_WIDTH_SB when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DATA_WIDTH_SB { PARAM_VALUE.DATA_WIDTH_SB } {
	# Procedure called to validate DATA_WIDTH_SB
	return true
}

proc update_PARAM_VALUE.GAP_WIDTH { PARAM_VALUE.GAP_WIDTH } {
	# Procedure called to update GAP_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.GAP_WIDTH { PARAM_VALUE.GAP_WIDTH } {
	# Procedure called to validate GAP_WIDTH
	return true
}

proc update_PARAM_VALUE.L2SPD_CAP { PARAM_VALUE.L2SPD_CAP } {
	# Procedure called to update L2SPD_CAP when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.L2SPD_CAP { PARAM_VALUE.L2SPD_CAP } {
	# Procedure called to validate L2SPD_CAP
	return true
}

proc update_PARAM_VALUE.MAX_LINK_SPEED_CAP { PARAM_VALUE.MAX_LINK_SPEED_CAP } {
	# Procedure called to update MAX_LINK_SPEED_CAP when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MAX_LINK_SPEED_CAP { PARAM_VALUE.MAX_LINK_SPEED_CAP } {
	# Procedure called to validate MAX_LINK_SPEED_CAP
	return true
}

proc update_PARAM_VALUE.MAX_LINK_WIDTH_CAP { PARAM_VALUE.MAX_LINK_WIDTH_CAP } {
	# Procedure called to update MAX_LINK_WIDTH_CAP when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MAX_LINK_WIDTH_CAP { PARAM_VALUE.MAX_LINK_WIDTH_CAP } {
	# Procedure called to validate MAX_LINK_WIDTH_CAP
	return true
}

proc update_PARAM_VALUE.MB_RX_FIFO_DEPTH { PARAM_VALUE.MB_RX_FIFO_DEPTH } {
	# Procedure called to update MB_RX_FIFO_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MB_RX_FIFO_DEPTH { PARAM_VALUE.MB_RX_FIFO_DEPTH } {
	# Procedure called to validate MB_RX_FIFO_DEPTH
	return true
}

proc update_PARAM_VALUE.MODULE_ID { PARAM_VALUE.MODULE_ID } {
	# Procedure called to update MODULE_ID when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MODULE_ID { PARAM_VALUE.MODULE_ID } {
	# Procedure called to validate MODULE_ID
	return true
}

proc update_PARAM_VALUE.NUM_LANES { PARAM_VALUE.NUM_LANES } {
	# Procedure called to update NUM_LANES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.NUM_LANES { PARAM_VALUE.NUM_LANES } {
	# Procedure called to validate NUM_LANES
	return true
}

proc update_PARAM_VALUE.N_BYTES { PARAM_VALUE.N_BYTES } {
	# Procedure called to update N_BYTES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.N_BYTES { PARAM_VALUE.N_BYTES } {
	# Procedure called to validate N_BYTES
	return true
}

proc update_PARAM_VALUE.PLL_PERIOD_NS { PARAM_VALUE.PLL_PERIOD_NS } {
	# Procedure called to update PLL_PERIOD_NS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PLL_PERIOD_NS { PARAM_VALUE.PLL_PERIOD_NS } {
	# Procedure called to validate PLL_PERIOD_NS
	return true
}

proc update_PARAM_VALUE.PMO_CAP { PARAM_VALUE.PMO_CAP } {
	# Procedure called to update PMO_CAP when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PMO_CAP { PARAM_VALUE.PMO_CAP } {
	# Procedure called to validate PMO_CAP
	return true
}

proc update_PARAM_VALUE.PSPT_CAP { PARAM_VALUE.PSPT_CAP } {
	# Procedure called to update PSPT_CAP when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PSPT_CAP { PARAM_VALUE.PSPT_CAP } {
	# Procedure called to validate PSPT_CAP
	return true
}

proc update_PARAM_VALUE.RX_ALIGN_DELAY { PARAM_VALUE.RX_ALIGN_DELAY } {
	# Procedure called to update RX_ALIGN_DELAY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.RX_ALIGN_DELAY { PARAM_VALUE.RX_ALIGN_DELAY } {
	# Procedure called to validate RX_ALIGN_DELAY
	return true
}

proc update_PARAM_VALUE.SB_RX_FIFO_DEPTH { PARAM_VALUE.SB_RX_FIFO_DEPTH } {
	# Procedure called to update SB_RX_FIFO_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SB_RX_FIFO_DEPTH { PARAM_VALUE.SB_RX_FIFO_DEPTH } {
	# Procedure called to validate SB_RX_FIFO_DEPTH
	return true
}

proc update_PARAM_VALUE.SB_TX_DN_CRD_INIT { PARAM_VALUE.SB_TX_DN_CRD_INIT } {
	# Procedure called to update SB_TX_DN_CRD_INIT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SB_TX_DN_CRD_INIT { PARAM_VALUE.SB_TX_DN_CRD_INIT } {
	# Procedure called to validate SB_TX_DN_CRD_INIT
	return true
}

proc update_PARAM_VALUE.SPMW_CAP { PARAM_VALUE.SPMW_CAP } {
	# Procedure called to update SPMW_CAP when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SPMW_CAP { PARAM_VALUE.SPMW_CAP } {
	# Procedure called to validate SPMW_CAP
	return true
}

proc update_PARAM_VALUE.SUPPORTEDVSWING_CAP { PARAM_VALUE.SUPPORTEDVSWING_CAP } {
	# Procedure called to update SUPPORTEDVSWING_CAP when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SUPPORTEDVSWING_CAP { PARAM_VALUE.SUPPORTEDVSWING_CAP } {
	# Procedure called to validate SUPPORTEDVSWING_CAP
	return true
}

proc update_PARAM_VALUE.TARR_CAP { PARAM_VALUE.TARR_CAP } {
	# Procedure called to update TARR_CAP when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TARR_CAP { PARAM_VALUE.TARR_CAP } {
	# Procedure called to validate TARR_CAP
	return true
}

proc update_PARAM_VALUE.VALID_PATTERN { PARAM_VALUE.VALID_PATTERN } {
	# Procedure called to update VALID_PATTERN when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.VALID_PATTERN { PARAM_VALUE.VALID_PATTERN } {
	# Procedure called to validate VALID_PATTERN
	return true
}


proc update_MODELPARAM_VALUE.DATA_WIDTH_MB { MODELPARAM_VALUE.DATA_WIDTH_MB PARAM_VALUE.DATA_WIDTH_MB } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DATA_WIDTH_MB}] ${MODELPARAM_VALUE.DATA_WIDTH_MB}
}

proc update_MODELPARAM_VALUE.DATA_WIDTH_SB { MODELPARAM_VALUE.DATA_WIDTH_SB PARAM_VALUE.DATA_WIDTH_SB } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DATA_WIDTH_SB}] ${MODELPARAM_VALUE.DATA_WIDTH_SB}
}

proc update_MODELPARAM_VALUE.NUM_LANES { MODELPARAM_VALUE.NUM_LANES PARAM_VALUE.NUM_LANES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.NUM_LANES}] ${MODELPARAM_VALUE.NUM_LANES}
}

proc update_MODELPARAM_VALUE.N_BYTES { MODELPARAM_VALUE.N_BYTES PARAM_VALUE.N_BYTES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.N_BYTES}] ${MODELPARAM_VALUE.N_BYTES}
}

proc update_MODELPARAM_VALUE.GAP_WIDTH { MODELPARAM_VALUE.GAP_WIDTH PARAM_VALUE.GAP_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.GAP_WIDTH}] ${MODELPARAM_VALUE.GAP_WIDTH}
}

proc update_MODELPARAM_VALUE.VALID_PATTERN { MODELPARAM_VALUE.VALID_PATTERN PARAM_VALUE.VALID_PATTERN } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.VALID_PATTERN}] ${MODELPARAM_VALUE.VALID_PATTERN}
}

proc update_MODELPARAM_VALUE.PLL_PERIOD_NS { MODELPARAM_VALUE.PLL_PERIOD_NS PARAM_VALUE.PLL_PERIOD_NS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PLL_PERIOD_NS}] ${MODELPARAM_VALUE.PLL_PERIOD_NS}
}

proc update_MODELPARAM_VALUE.RX_ALIGN_DELAY { MODELPARAM_VALUE.RX_ALIGN_DELAY PARAM_VALUE.RX_ALIGN_DELAY } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.RX_ALIGN_DELAY}] ${MODELPARAM_VALUE.RX_ALIGN_DELAY}
}

proc update_MODELPARAM_VALUE.CLK_FRQ_HZ { MODELPARAM_VALUE.CLK_FRQ_HZ PARAM_VALUE.CLK_FRQ_HZ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CLK_FRQ_HZ}] ${MODELPARAM_VALUE.CLK_FRQ_HZ}
}

proc update_MODELPARAM_VALUE.MAX_LINK_WIDTH_CAP { MODELPARAM_VALUE.MAX_LINK_WIDTH_CAP PARAM_VALUE.MAX_LINK_WIDTH_CAP } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MAX_LINK_WIDTH_CAP}] ${MODELPARAM_VALUE.MAX_LINK_WIDTH_CAP}
}

proc update_MODELPARAM_VALUE.MAX_LINK_SPEED_CAP { MODELPARAM_VALUE.MAX_LINK_SPEED_CAP PARAM_VALUE.MAX_LINK_SPEED_CAP } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MAX_LINK_SPEED_CAP}] ${MODELPARAM_VALUE.MAX_LINK_SPEED_CAP}
}

proc update_MODELPARAM_VALUE.SPMW_CAP { MODELPARAM_VALUE.SPMW_CAP PARAM_VALUE.SPMW_CAP } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SPMW_CAP}] ${MODELPARAM_VALUE.SPMW_CAP}
}

proc update_MODELPARAM_VALUE.PMO_CAP { MODELPARAM_VALUE.PMO_CAP PARAM_VALUE.PMO_CAP } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PMO_CAP}] ${MODELPARAM_VALUE.PMO_CAP}
}

proc update_MODELPARAM_VALUE.PSPT_CAP { MODELPARAM_VALUE.PSPT_CAP PARAM_VALUE.PSPT_CAP } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PSPT_CAP}] ${MODELPARAM_VALUE.PSPT_CAP}
}

proc update_MODELPARAM_VALUE.L2SPD_CAP { MODELPARAM_VALUE.L2SPD_CAP PARAM_VALUE.L2SPD_CAP } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.L2SPD_CAP}] ${MODELPARAM_VALUE.L2SPD_CAP}
}

proc update_MODELPARAM_VALUE.SUPPORTEDVSWING_CAP { MODELPARAM_VALUE.SUPPORTEDVSWING_CAP PARAM_VALUE.SUPPORTEDVSWING_CAP } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SUPPORTEDVSWING_CAP}] ${MODELPARAM_VALUE.SUPPORTEDVSWING_CAP}
}

proc update_MODELPARAM_VALUE.CLK_MODE_CAP { MODELPARAM_VALUE.CLK_MODE_CAP PARAM_VALUE.CLK_MODE_CAP } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CLK_MODE_CAP}] ${MODELPARAM_VALUE.CLK_MODE_CAP}
}

proc update_MODELPARAM_VALUE.CLK_PHASE_CAP { MODELPARAM_VALUE.CLK_PHASE_CAP PARAM_VALUE.CLK_PHASE_CAP } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CLK_PHASE_CAP}] ${MODELPARAM_VALUE.CLK_PHASE_CAP}
}

proc update_MODELPARAM_VALUE.TARR_CAP { MODELPARAM_VALUE.TARR_CAP PARAM_VALUE.TARR_CAP } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TARR_CAP}] ${MODELPARAM_VALUE.TARR_CAP}
}

proc update_MODELPARAM_VALUE.ADVANCED_PKG_CAP { MODELPARAM_VALUE.ADVANCED_PKG_CAP PARAM_VALUE.ADVANCED_PKG_CAP } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ADVANCED_PKG_CAP}] ${MODELPARAM_VALUE.ADVANCED_PKG_CAP}
}

proc update_MODELPARAM_VALUE.MODULE_ID { MODELPARAM_VALUE.MODULE_ID PARAM_VALUE.MODULE_ID } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MODULE_ID}] ${MODELPARAM_VALUE.MODULE_ID}
}

proc update_MODELPARAM_VALUE.MB_RX_FIFO_DEPTH { MODELPARAM_VALUE.MB_RX_FIFO_DEPTH PARAM_VALUE.MB_RX_FIFO_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MB_RX_FIFO_DEPTH}] ${MODELPARAM_VALUE.MB_RX_FIFO_DEPTH}
}

proc update_MODELPARAM_VALUE.SB_TX_DN_CRD_INIT { MODELPARAM_VALUE.SB_TX_DN_CRD_INIT PARAM_VALUE.SB_TX_DN_CRD_INIT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SB_TX_DN_CRD_INIT}] ${MODELPARAM_VALUE.SB_TX_DN_CRD_INIT}
}

proc update_MODELPARAM_VALUE.SB_RX_FIFO_DEPTH { MODELPARAM_VALUE.SB_RX_FIFO_DEPTH PARAM_VALUE.SB_RX_FIFO_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SB_RX_FIFO_DEPTH}] ${MODELPARAM_VALUE.SB_RX_FIFO_DEPTH}
}

