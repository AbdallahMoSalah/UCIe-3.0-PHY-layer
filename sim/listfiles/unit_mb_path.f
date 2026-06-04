# Full MainBand datapath integration:
#   Mapper -> LFSR_TX -> MB_SERIALIZER x16 -> MB_DESERIALIZER x16 -> LFSR_RX -> Demapper
# Production mapper/serializer/demapper + SPEC-FIXED lfsr_tx / deserializer / lfsr_rx.
rtl/MainBand/MAPPER/Mapper.sv
rtl/MainBand/unsued/LFSR_TX.sv
rtl/MainBand/MB_Serializer/mb_serializer.sv
rtl/MainBand/unsued/mb_deserializer.sv
rtl/MainBand/unsued/LFSR_RX.sv
rtl/MainBand/DEMAPPER/Demapper.sv

# Testbench
rtl/MainBand/unsued/mb_path_tb.sv
