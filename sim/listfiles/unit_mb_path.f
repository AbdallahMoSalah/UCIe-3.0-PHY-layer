# Full MainBand datapath integration:
#   Mapper -> LFSR_TX -> MB_SERIALIZER x16 -> MB_DESERIALIZER x16 -> LFSR_RX -> Demapper
# Production mapper/serializer/demapper + SPEC-FIXED lfsr_tx / deserializer / lfsr_rx.
rtl/MainBand/tx/Mapper.sv
rtl/MainBand/tx/LFSR_TX.sv
rtl/MainBand/tx/mb_serializer.sv
rtl/MainBand/rx/mb_deserializer.sv
rtl/MainBand/rx/LFSR_RX.sv
rtl/MainBand/rx/Demapper.sv

# Testbench
rtl/MainBand/rx/unused/mb_path_tb.sv
