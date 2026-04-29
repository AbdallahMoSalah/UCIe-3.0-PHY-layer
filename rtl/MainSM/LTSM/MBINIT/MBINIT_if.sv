interface ucie_mb_cap_if;

    ////////////////////////////////////////////////////////
    // LOCAL
    ////////////////////////////////////////////////////////
    logic        local_is_x8;
    logic [3:0]  local_max_speed;
    logic        local_sbfe;
    logic        local_tarr;

    logic        local_l2spd;
    logic        local_pspt;
    logic        local_so;
    logic        local_pmo;
    logic        local_mtp;

    ////////////////////////////////////////////////////////
    // PARTNER
    ////////////////////////////////////////////////////////
    logic        partner_is_x8;
    logic [3:0]  partner_max_speed;
    logic        partner_sbfe;
    logic        partner_tarr;

    logic        partner_l2spd;
    logic        partner_pspt;
    logic        partner_so;
    logic        partner_pmo;
    logic        partner_mtp;

    ////////////////////////////////////////////////////////
    // NEGOTIATED
    ////////////////////////////////////////////////////////
    logic        use_x8_mode;
    logic [3:0]  negotiated_speed;
    logic        negotiated_sbfe;
    logic        negotiated_tarr;

    logic        negotiated_l2spd;
    logic        negotiated_pspt;
    logic        negotiated_so;
    logic        negotiated_pmo;
    logic        negotiated_mtp;

    ////////////////////////////////////////////////////////
    // MODPORTS
    ////////////////////////////////////////////////////////

    modport mbinit (
        // inputs
        input  local_is_x8,
        input  local_max_speed,
        input  local_sbfe,
        input  local_tarr,

        input  local_l2spd,
        input  local_pspt,
        input  local_so,
        input  local_pmo,
        input  local_mtp,

        // outputs
        output partner_is_x8,
        output partner_max_speed,
        output partner_sbfe,
        output partner_tarr,

        output partner_l2spd,
        output partner_pspt,
        output partner_so,
        output partner_pmo,
        output partner_mtp,

        output use_x8_mode,
        output negotiated_speed,
        output negotiated_sbfe,
        output negotiated_tarr,

        output negotiated_l2spd,
        output negotiated_pspt,
        output negotiated_so,
        output negotiated_pmo,
        output negotiated_mtp
    );

    modport consumer (
        input use_x8_mode,
        input negotiated_speed
        //input negotiated_sbfe,
        //input negotiated_tarr
    );

    modport regfile (
        output local_is_x8,
        output local_max_speed,
        output local_sbfe,
        output local_tarr,

        output local_l2spd,
        output local_pspt,
        output local_so,
        output local_pmo,
        output local_mtp
    );

endinterface