package Link_Controller_tb_pkg;

    import sb_pkg::*;

    typedef enum logic [0:0] {
        Link = 1'b0,
        Adapter = 1'b1
    } type_m_e;


    class Link_Controller_class;

        rand logic rst_n;

        rand logic [127:0] Link_msg_send;
        rand logic Link_vld_send;
        rand logic [127:0] Adapter_msg_send;
        rand logic Adapter_vld_send;
        
        logic Adapter_ready;
        logic Link_ready;

        rand logic ser_ready;

        logic [127:0] msg_rcvd;
        logic msg_vld_rcvd;
        logic [127:0] Adapter_msg_rcvd;
        logic Adapter_vld_rcvd;
        logic [127:0] Link_msg_rcvd;
        logic Link_vld_rcvd;


        logic [127:0] msg_send;
        logic msg_vld_send;
        
    endclass

endpackage