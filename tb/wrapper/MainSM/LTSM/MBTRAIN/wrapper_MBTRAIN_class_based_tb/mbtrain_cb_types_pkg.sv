package mbtrain_cb_types_pkg;
    import ltsm_state_n_pkg::*;

    typedef enum {GROUP_A_NORMAL, GROUP_B_SPEED, GROUP_C_WIDTH, GROUP_D_PHYRETRAIN, GROUP_E_FAILURE, GROUP_F_ASYNC} mbtrain_scenario_group_e;
    typedef enum {EXIT_LINKINIT, EXIT_SPEEDIDLE_LOOP, EXIT_REPAIR_LOOP, EXIT_PHYRETRAIN, EXIT_TRAINERROR, EXIT_TIMEOUT, EXIT_IDLE} mbtrain_expected_exit_e;
    typedef enum {WIDTH_X16, WIDTH_X8, WIDTH_X4} mbtrain_width_e;
    typedef enum logic [2:0] {SPEED_4G=3'b000, SPEED_8G=3'b001, SPEED_12G=3'b010, SPEED_16G=3'b011, SPEED_24G=3'b100, SPEED_32G=3'b101, SPEED_48G=3'b110, SPEED_64G=3'b111} mbtrain_speed_e;
    typedef struct {
        string name;
        mbtrain_width_e width;
        mbtrain_speed_e speed;
        mbtrain_expected_exit_e expected_exit;
        state_n_e state_path_q[$];
        logic [15:0] d2c_pass_mask;
        logic [15:0] linkspeed_pass_q[$];
        bit PHY_IN_RETRAIN;
        bit params_changed;
        logic [2:0] expected_rx_mask;
        logic [2:0] expected_tx_mask;
        bit expected_timeout;
        bit inject_soft_reset_mid_sequence;
        bit inject_disable_mid_sequence;
        bit suppress_response_en;
        logic [7:0] suppress_response_msg;
    } mbtrain_scenario_s;
endpackage
