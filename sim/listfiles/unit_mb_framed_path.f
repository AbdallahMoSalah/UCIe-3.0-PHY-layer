# Option-A framed MainBand datapath: data lanes framed by a real valid lane
# (valid-lane word_load) instead of a TB backdoor. All canonical unsued/ copies.
rtl/MainBand/tx/Mapper.sv
rtl/MainBand/tx/LFSR_TX.sv
rtl/MainBand/tx/mb_serializer.sv
rtl/MainBand/tx/Valid_tx.sv
rtl/MainBand/rx/mb_des_valid.sv
rtl/MainBand/rx/unused/mb_deserializer_framed.sv
rtl/MainBand/rx/LFSR_RX.sv
rtl/MainBand/rx/Demapper.sv

# Testbench
rtl/MainBand/rx/unused/mb_framed_path_tb.sv
