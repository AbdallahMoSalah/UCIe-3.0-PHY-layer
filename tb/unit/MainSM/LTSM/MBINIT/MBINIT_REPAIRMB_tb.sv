`timescale 1ns/1ps
import UCIe_pkg::*;

module MBINIT_REPAIRMB_tb;

//////////////////////////////////////////////////
// CLOCK / RESET
//////////////////////////////////////////////////
logic clk;
logic rst_n;

initial clk = 0;
always #500 clk = ~clk;

//////////////////////////////////////////////////
// INTERFACES
//////////////////////////////////////////////////
ucie_mb_cap_if cap_if_master();
ucie_mb_cap_if cap_if_partner();

internal_ltsm_if d2c_if_master(.lclk(clk), .rst_n(rst_n));
internal_ltsm_if d2c_if_partner(.lclk(clk), .rst_n(rst_n));

assign cap_if_master.use_x8_mode  = 1;
assign cap_if_partner.use_x8_mode = 1;

//////////////////////////////////////////////////
// MASTER SIGNALS
//////////////////////////////////////////////////
logic m_enable;
logic m_done;
logic m_error;

logic m_rx_valid;
msg_no_e m_rx_msg_id;
logic [15:0] m_rx_MsgInfo;
logic [63:0] m_rx_data;

logic m_tx_valid;
msg_no_e m_tx_msg_id;
logic [15:0] m_tx_MsgInfo;
logic [63:0] m_tx_data;

logic m_timeout_error;

//////////////////////////////////////////////////
// PARTNER SIGNALS
//////////////////////////////////////////////////
logic p_enable;
logic p_done;
logic p_error;

logic p_rx_valid;
msg_no_e p_rx_msg_id;
logic [15:0] p_rx_MsgInfo;
logic [63:0] p_rx_data;

logic p_tx_valid;
msg_no_e p_tx_msg_id;
logic [15:0] p_tx_MsgInfo;
logic [63:0] p_tx_data;

logic p_timeout_error;

//////////////////////////////////////////////////
// LINK CONNECTION
//////////////////////////////////////////////////
assign p_rx_valid   = m_tx_valid;
assign p_rx_msg_id  = m_tx_msg_id;
assign p_rx_MsgInfo = m_tx_MsgInfo;
assign p_rx_data    = m_tx_data;

assign m_rx_valid   = p_tx_valid;
assign m_rx_msg_id  = p_tx_msg_id;
assign m_rx_MsgInfo = p_tx_MsgInfo;
assign m_rx_data    = p_tx_data;

//////////////////////////////////////////////////
// PHY CONTROL SIGNALS
//////////////////////////////////////////////////
logic m_tx_data_status;
logic m_tx_clk_status;
logic m_tx_track_status;
logic m_tx_valid_status;

logic m_rx_data_status;
logic m_rx_clk_status;
logic m_rx_track_status;
logic m_rx_valid_status;


logic p_tx_data_status;
logic p_tx_clk_status;
logic p_tx_track_status;
logic p_tx_valid_status;

logic p_rx_data_status;
logic p_rx_clk_status;
logic p_rx_track_status;
logic p_rx_valid_status;

//////////////////////////////////////////////////
// DUTs
//////////////////////////////////////////////////
MBINIT_REPAIRMB master (
    .clk(clk),
    .rst_n(rst_n),
    .cap_if(cap_if_master),
    .d2c_test_if(d2c_if_master),
    .mb_repairmb_enable(m_enable),
    .mb_repairmb_done(m_done),
    .mb_repairmb_error(m_error),
    .mb_repairmb_rx_valid(m_rx_valid),
    .mb_repairmb_rx_msg_id(m_rx_msg_id),
    .mb_repairmb_rx_MsgInfo(m_rx_MsgInfo),
    .mb_repairmb_rx_data_Field(m_rx_data),
    .mb_repairmb_tx_valid(m_tx_valid),
    .mb_repairmb_tx_msg_id(m_tx_msg_id),
    .mb_repairmb_tx_MsgInfo(m_tx_MsgInfo),
    .mb_repairmb_tx_data_Field(m_tx_data),
    .timeout_error(m_timeout_error),

    .mb_tx_data_status(m_tx_data_status),
    .mb_tx_clk_status(m_tx_clk_status),
    .mb_tx_track_status(m_tx_track_status),
    .mb_tx_valid_status(m_tx_valid_status),

    .mb_rx_data_status(m_rx_data_status),
    .mb_rx_clk_status(m_rx_clk_status),
    .mb_rx_track_status(m_rx_track_status),
    .mb_rx_valid_status(m_rx_valid_status)
);

MBINIT_REPAIRMB partner (
    .clk(clk),
    .rst_n(rst_n),
    .cap_if(cap_if_partner),
    .d2c_test_if(d2c_if_partner),
    .mb_repairmb_enable(p_enable),
    .mb_repairmb_done(p_done),
    .mb_repairmb_error(p_error),
    .mb_repairmb_rx_valid(p_rx_valid),
    .mb_repairmb_rx_msg_id(p_rx_msg_id),
    .mb_repairmb_rx_MsgInfo(p_rx_MsgInfo),
    .mb_repairmb_rx_data_Field(p_rx_data),
    .mb_repairmb_tx_valid(p_tx_valid),
    .mb_repairmb_tx_msg_id(p_tx_msg_id),
    .mb_repairmb_tx_MsgInfo(p_tx_MsgInfo),
    .mb_repairmb_tx_data_Field(p_tx_data),
    .timeout_error(p_timeout_error),

    .mb_tx_data_status(p_tx_data_status),
    .mb_tx_clk_status(p_tx_clk_status),
    .mb_tx_track_status(p_tx_track_status),
    .mb_tx_valid_status(p_tx_valid_status),

    .mb_rx_data_status(p_rx_data_status),
    .mb_rx_clk_status(p_rx_clk_status),
    .mb_rx_track_status(p_rx_track_status),
    .mb_rx_valid_status(p_rx_valid_status)
);

//////////////////////////////////////////////////
// INIT
//////////////////////////////////////////////////
initial begin
    rst_n = 0;
    m_enable = 0;
    p_enable = 0;

    d2c_if_master.test_d2c_done = 0;
    d2c_if_partner.test_d2c_done = 0;

    d2c_if_master.d2c_perlane_err = 0;
    d2c_if_partner.d2c_perlane_err = 0;

    repeat(5) @(posedge clk);
    rst_n = 1;

    // Assert enables simultaneously
    @(posedge clk);
    m_enable = 1;
    p_enable = 1;
end

//////////////////////////////////////////////////
// RETRY ASSERTION (EDGE DETECTION)
//////////////////////////////////////////////////
logic retry_seen;
logic retry_prev;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        retry_seen <= 0;
        retry_prev <= 0;
    end
    else begin
        if((master.retry_start || partner.retry_start) && !retry_prev) begin
            if(retry_seen) begin
                $error("ERROR: Retry happened more than once!");
                $finish;
            end
            retry_seen <= 1;
        end
        retry_prev <= (master.retry_start || partner.retry_start);
    end
end

//////////////////////////////////////////////////
// DEBUG
//////////////////////////////////////////////////
always @(posedge clk) begin
    // $display("T=%0t | M_state=%0d | P_state=%0d | M_local=%b P_local=%b final=%b",
    //     $time, master.current_state, partner.current_state,
    //     master.local_lane_map, partner.local_lane_map, master.final_lane_map);
    $display("STATE=%0d local=%b partner=%b final=%b degrade_np=%b",
    master.current_state,
    master.local_lane_map,
    partner.local_lane_map,
    master.final_lane_map,
    master.degrade_not_possible_r);
end

//////////////////////////////////////////////////
// MAIN TEST FLOW
//////////////////////////////////////////////////
initial begin
    wait(rst_n);

    $display("==== START TEST ====");

    //////////////////////////////////////////
    // TEST 1: FORCE RETRY
    //////////////////////////////////////////
    wait(d2c_if_master.tx_pt_en && d2c_if_partner.tx_pt_en);
    repeat(2) @(posedge clk);

    $display("==== TEST 1: FORCE RETRY ====");

    d2c_if_master.d2c_perlane_err  = 16'hFF00;
    d2c_if_partner.d2c_perlane_err = 16'hFF0F; // Mismatch to force retry!

    d2c_if_master.test_d2c_done = 1;
    d2c_if_partner.test_d2c_done = 1;

    @(posedge clk);
    d2c_if_master.test_d2c_done = 0;
    d2c_if_partner.test_d2c_done = 0;

    //////////////////////////////////////////
    // WAIT RETRY (EDGE)
    //////////////////////////////////////////
    wait(master.retry_start || partner.retry_start);
    wait(!(master.retry_start || partner.retry_start));

    $display("==== RETRY DETECTED ====");

    //////////////////////////////////////////
    // TEST 2: STABLE
    //////////////////////////////////////////
    wait(d2c_if_master.tx_pt_en && d2c_if_partner.tx_pt_en);
    repeat(2) @(posedge clk);

    $display("==== TEST 2: STABLE ====");

    d2c_if_master.d2c_perlane_err  = 16'hFF0F;
    d2c_if_partner.d2c_perlane_err = 16'hFF0F; // Same, should stabilize

    d2c_if_master.test_d2c_done = 1;
    d2c_if_partner.test_d2c_done = 1;

    @(posedge clk);
    d2c_if_master.test_d2c_done = 0;
    d2c_if_partner.test_d2c_done = 0;
end

//////////////////////////////////////////////////
// STOP CONDITIONS
//////////////////////////////////////////////////
always @(posedge clk) begin
    if(m_done && p_done) begin
        $display("==== DONE = 1 (PASS) ====");
        $finish;
    end
    else if(m_error || p_error) begin
        $display("==== ERROR = 1 (FAIL) ====");
        $finish;
    end
end

endmodule
