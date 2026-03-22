package reset_state_pkg;
        typedef enum logic[3:0] {idle,
                             le_req, 
                             le_resp, 
                             linkerror, 
                             d_req, 
                             d_resp, 
                             disabled, 
                             lr_req, 
                             lr_resp, 
                             linkreset, 
                             NOP_rcvd, 
                             training, 
                             INPP, 
                             active_hs, 
                             active,
                             state_disable } reset_state;
endpackage