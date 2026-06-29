// =============================================================================
// mbtrain_cb_transaction.sv — SB event record
// =============================================================================
class mbtrain_cb_transaction;
    import UCIe_pkg::*;
    import ltsm_state_n_pkg::*;
    import mbtrain_cb_types_pkg::*;

    // Simulation time this transaction was captured
    time            timestamp;

    // SB message fields
    logic [7:0]     msg;
    logic [15:0]    msginfo;
    logic [63:0]    data;

    // Direction: 0 = DUT→TB (TX monitor), 1 = TB→DUT (RX inject)
    bit             is_rx;

    // MBTRAIN substate at the time of capture
    state_n_e       substate;

    // Scenario this transaction belongs to
    string          scenario_name;

    function new();
        timestamp     = $time;
        msg           = 8'h00;
        msginfo       = 16'h0000;
        data          = 64'h0;
        is_rx         = 0;
        substate      = LOG_NOP;
        scenario_name = "";
    endfunction

    function string to_string();
        return $sformatf("[%0t] %s sub=%s msg=0x%02X info=0x%04X",
            timestamp,
            is_rx ? "RX" : "TX",
            substate.name(),
            msg,
            msginfo);
    endfunction

endclass
