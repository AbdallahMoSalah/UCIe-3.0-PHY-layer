# Option-A framed MainBand datapath: data lanes framed by a real valid lane
# (valid-lane word_load) instead of a TB backdoor. All canonical unsued/ copies.
rtl/MainBand/tx/unit_mapper.sv
rtl/MainBand/tx/unit_lfsr_tx.sv
rtl/MainBand/tx/unit_mb_serializer.sv
rtl/MainBand/tx/unit_valid_tx.sv
rtl/MainBand/rx/unit_mb_des_valid.sv
rtl/MainBand/rx/unused/unit_mb_deserializer_framed.sv
rtl/MainBand/rx/unit_lfsr_rx.sv
rtl/MainBand/rx/unit_demapper.sv

# Testbench
tb/unit/mainband/rx/unit_mb_framed_path_tb.sv
