package sb_serializer_tb_pkg;

    typedef enum bit [1:0]{WITHOUT_RESET, WITH_RESET, NORMAL} testType_t;
    typedef enum logic [1:0] {
        IDLE,
        SHIFT,
        GAP
    } state_t;

    parameter DATA_WIDTH = 64;
    parameter GAP_WIDTH  = 32;

    class sb_serializer_class;
        
        logic clk;

        rand logic rst_n;

        rand logic [DATA_WIDTH-1:0] tx_parallel_data;
        rand logic tx_data_valid;
        logic tx_ready;
        state_t Prev_state;
        state_t state;

        logic [DATA_WIDTH-1:0] Prev_tx_parallel_data;
        logic Prev_tx_data_valid = 0;
        logic Prev_tx_ready = 1;

        logic tx_serial_out;
        logic TXCKSB;
 

        testType_t testtype = WITHOUT_RESET;


        constraint rst_constraint{
            if(testtype == WITHOUT_RESET){
                rst_n == 1;
            }else if(testtype == WITH_RESET){
                rst_n == 0;
            }
            else {
                rst_n dist { 1 :/ 80, 0 :/20};
            }
            
        }


        constraint data_send_constraint{
            if(tx_ready == 0 ){
                tx_parallel_data == Prev_tx_parallel_data;
            }
        }

        constraint vld_send_constraint{
            if(tx_ready == 0  && Prev_tx_ready == 0 && Prev_tx_data_valid == 1){
                tx_data_valid == 1;
            }
            else if(tx_ready == 0  && Prev_tx_ready == 0 && Prev_tx_data_valid == 0){
                tx_data_valid dist { 0 :/ 100, 1 :/ 5};
            }
            else {
                tx_data_valid dist { 1 :/ 70, 0 :/ 30};
            }
        }   

        covergroup cvr_gp;
            trans_state_cp : coverpoint {Prev_state, state} {

                bins idle_to_shift = { {IDLE,SHIFT} };
                bins shift_to_gap  = { {SHIFT,GAP} };
                bins gap_to_idle   = { {GAP,IDLE} };
                bins gap_to_shift  = { {GAP,SHIFT} };
                bins shift_to_idle = { {SHIFT, IDLE}};
                illegal_bins illegal = {{IDLE, GAP}};
            }
            state_cp : coverpoint state {
                bins idle = {IDLE};
                bins gap = {GAP};
                bins shift = {SHIFT};
            }
            valid_cp : coverpoint tx_data_valid;
            ready_cp : coverpoint tx_ready;
            valid_ready : cross valid_cp, ready_cp;
            valid_ready_state : cross valid_cp, ready_cp, state_cp{
                option.cross_auto_bin_max   = 0;
                bins gap_0_0 = binsof(valid_cp) intersect{0} && binsof(ready_cp) intersect{0} && binsof(state_cp.gap);
                bins shift_0_0 = binsof(valid_cp) intersect{0} && binsof(ready_cp) intersect{0} && binsof(state_cp.shift);
                bins idle_1_1 = binsof(valid_cp) intersect{1} && binsof(ready_cp) intersect{1} && binsof(state_cp.idle);
                bins gap_1_1 = binsof(valid_cp) intersect{1} && binsof(ready_cp) intersect{1} && binsof(state_cp.gap);
            }

        endgroup

        function new();
           cvr_gp = new;   
        endfunction

        function void sample_cov(state_t s);
            state = s;
            cvr_gp.sample();
            Prev_state = s;
        endfunction



        function void post_randomize();
            Prev_tx_parallel_data = tx_parallel_data;
            Prev_tx_ready = tx_ready;
            Prev_tx_data_valid = tx_data_valid;
        endfunction

        
    endclass
endpackage