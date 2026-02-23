package sb_pkg;

    typedef enum logic [4:0] {
        SB_32_MEM_READ   = 5'b00000,
        SB_32_MEM_WRITE  = 5'b00001,
        SB_32_DMS_REG_READ   = 5'b00010,
        SB_32_DMS_REG_WRITE  = 5'b00011,
        SB_32_CFG_READ   = 5'b00100,
        SB_32_CFG_WRITE  = 5'b00101,
        SB_64_MEM_READ   = 5'b01000,
        SB_64_MEM_WRITE  = 5'b01001,
        SB_64_DMS_REG_READ   = 5'b01010,
        SB_64_DMS_REG_WRITE  = 5'b01011,
        SB_64_CFG_READ   = 5'b01100,
        SB_64_CFG_WRITE  = 5'b01101,
        SB_COMPLETION_WITHOUT_DATA     = 5'b10000,
        SB_COMPLETION_WITH_32_DATA        = 5'b10001,
        SB_MSG_WITHOUT_DATA        = 5'b10010,
        SB_MNGT_PORT_MSG_WITHOUT_DATA = 5'b10111,
        SB_MNGT_PORT_MSG_WITH_DATA    = 5'b11000,
        SB_COMPLETION_WITH_64_DATA        = 5'b11001,
        SB_MSG_WITH_64_DATA        = 5'b11011,
        SB_PRIORITY_MSG1 = 5'b11110,
        SB_PRIORITY_MSG2   = 5'b11111
    } sb_opcode_e;  

    typedef enum logic [2:0] {
        STACK0   = 3'b000,
        ADAPTER = 3'b001,
        PHY = 3'b010,
        MNGT_PORT_src = 3'b011,
        STACK1  = 3'b100  
    } sb_srcid_e;   

    typedef enum logic [2:0] {
        LOCAL_ADAPTER = 3'b001,
        LOCAL_PHY = 3'b010,
        REMOTE_ADAPTER = 3'b101,
        REMOTE_PHY = 3'b110,
        REMOTE_REG_ACCESS = 3'b100,
        MNGT_PORT_dst = 3'b111
    } sb_dstid_e;   

    typedef enum logic [3:0] {
        ACTIVE_REQ = 4'b0000,
        L1_REQ = 4'b0001,
        L2_REQ = 4'b0010,
        LINK_RESET_REQ = 4'b0011,
        LINK_ERROR_REQ = 4'b0100,
        RETRAIN_REQ = 4'b0101,
        DISABLE_REQ = 4'b0110,
        ACTIVE_RSP = 4'b0111,
        PMNAK_RSP = 4'b1000,
        L1_RSP = 4'b1001,
        L2_RSP = 4'b1010,
        LINK_RESET_RSP = 4'b1011,
        LINK_ERROR_RSP = 4'b1100,
        RETRAIN_RSP = 4'b1101,
        DISABLE_RSP = 4'b1110,
        NOP = 4'b1111
    } sb_rdi_msg_no_e;

typedef struct packed {

    logic        dp;            // [63]
    logic        cp;            // [62]
    logic [2:0]  rsvd2;         // [61:59]
    sb_dstid_e   dstid;         // [58:56]
    logic [15:0] MsgInfo;       // [55:40]
    logic [7:0]  MsgSubcode;    // [39:32]

    sb_srcid_e   srcid;         // [31:29]
    logic [6:0]  rsvd1;         // [28:22]
    logic [7:0]  msgcode;       // [21:14]
    logic [8:0]  rsvd0;         // [13:5]
    sb_opcode_e  opcode;        // [4:0]
    
} sb_header_t;


endpackage