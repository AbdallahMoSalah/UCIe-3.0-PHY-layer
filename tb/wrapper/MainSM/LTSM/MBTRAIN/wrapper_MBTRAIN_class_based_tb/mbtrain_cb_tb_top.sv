// =============================================================================
// mbtrain_cb_tb_top.sv — Thin top-level wrapper
// The real top module is wrapper_MBTRAIN_class_based_tb.
// This file satisfies any simulator that requires a module named mbtrain_cb_tb_top.
// =============================================================================
module mbtrain_cb_tb_top;
    wrapper_MBTRAIN_class_based_tb tb();
endmodule
