# Full MainBand datapath integration:
#   Mapper -> LFSR_TX -> unit_mb_serializer x16 -> unit_mb_deserializer x16 -> LFSR_RX -> Demapper
# Production mapper/serializer/demapper + SPEC-FIXED lfsr_tx / deserializer / lfsr_rx.
rtl/MainBand/tx/unit_mapper.sv
rtl/MainBand/tx/unit_lfsr_tx.sv
rtl/MainBand/tx/unit_mb_serializer.sv
rtl/MainBand/rx/unit_mb_deserializer.sv
rtl/MainBand/rx/unit_lfsr_rx.sv
rtl/MainBand/rx/unit_demapper.sv

# Testbench
tb/unit/mainband/rx/unit_mb_path_tb.sv
