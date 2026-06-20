import os
import re

files_to_check = [
    "rtl/MainSM/LTSM/LTSM_wrapper.sv",
    "rtl/MainSM/LTSM/MBTRAIN/DATATRAINCENTER1/unit_DATATRAINCENTER1_local.sv",
    "rtl/MainSM/LTSM/MBTRAIN/DATATRAINCENTER1/wrapper_DATATRAINCENTER1.sv",
    "rtl/MainSM/LTSM/MBTRAIN/DATATRAINCENTER2/unit_DATATRAINCENTER2_local.sv",
    "rtl/MainSM/LTSM/MBTRAIN/DATATRAINCENTER2/wrapper_DATATRAINCENTER2.sv",
    "rtl/MainSM/LTSM/MBTRAIN/DATATRAINVREF/unit_DATATRAINVREF_partner.sv",
    "rtl/MainSM/LTSM/MBTRAIN/DATATRAINVREF/wrapper_DATATRAINVREF.sv",
    "rtl/MainSM/LTSM/MBTRAIN/DATAVREF/unit_DATAVREF_partner.sv",
    "rtl/MainSM/LTSM/MBTRAIN/DATAVREF/wrapper_DATAVREF.sv",
    "rtl/MainSM/LTSM/MBTRAIN/LINKSPEED/wrapper_LINKSPEED.sv",
    "rtl/MainSM/LTSM/MBTRAIN/MBTRAIN_overview.md",
    "rtl/MainSM/LTSM/MBTRAIN/REPAIR/unit_REPAIR_local.sv",
    "rtl/MainSM/LTSM/MBTRAIN/REPAIR/unit_REPAIR_partner.sv",
    "rtl/MainSM/LTSM/MBTRAIN/REPAIR/wrapper_REPAIR.sv",
    "rtl/MainSM/LTSM/MBTRAIN/RXCLKCAL/unit_RXCLKCAL_partner.sv",
    "rtl/MainSM/LTSM/MBTRAIN/RXCLKCAL/wrapper_RXCLKCAL.sv",
    "rtl/MainSM/LTSM/MBTRAIN/RXDESKEW/unit_RXDESKEW_partner.sv",
    "rtl/MainSM/LTSM/MBTRAIN/RXDESKEW/wrapper_RXDESKEW.sv",
    "rtl/MainSM/LTSM/MBTRAIN/SPEEDIDLE/unit_SPEEDIDLE_local.sv",
    "rtl/MainSM/LTSM/MBTRAIN/SPEEDIDLE/unit_SPEEDIDLE_partner.sv",
    "rtl/MainSM/LTSM/MBTRAIN/SPEEDIDLE/wrapper_SPEEDIDLE.sv",
    "rtl/MainSM/LTSM/MBTRAIN/TXSELFCAL/wrapper_TXSELFCAL.sv",
    "rtl/MainSM/LTSM/MBTRAIN/VALTRAINCENTER/wrapper_VALTRAINCENTER.sv",
    "rtl/MainSM/LTSM/MBTRAIN/VALTRAINVREF/unit_VALTRAINVREF_partner.sv",
    "rtl/MainSM/LTSM/MBTRAIN/VALTRAINVREF/wrapper_VALTRAINVREF.sv",
    "rtl/MainSM/LTSM/MBTRAIN/VALVREF/unit_VALVREF_partner.sv",
    "rtl/MainSM/LTSM/MBTRAIN/VALVREF/wrapper_VALVREF.sv",
    "rtl/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN.sv"
]

pattern = re.compile(r'mb_tx_(clk|data|val|trk)_lane_sel')

for filepath in files_to_check:
    if not os.path.exists(filepath): continue
    with open(filepath, "r") as f:
        lines = f.readlines()
    
    new_lines = []
    for line in lines:
        if not pattern.search(line):
            new_lines.append(line)
        else:
            # Check if this line looks like something we shouldn't just blindly remove
            # Like if it's the last port and we leave a trailing comma issue, etc.
            # But wait, python script will just do it. We can run verible-verilog-syntax to check.
            pass
            
    with open(filepath, "w") as f:
        f.writelines(new_lines)
