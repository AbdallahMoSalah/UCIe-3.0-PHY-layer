package LinK_Arbiter_pkg;
    
class Link_Arbiter_tb_class;

rand logic [127:0] LINK_msg;
rand logic LINK_vld;

rand logic [127:0] adapter_msg;
rand logic adapter_not_empty;

rand logic mapper_ready;

// expected outputs
logic [127:0] exp_msg;
logic exp_valid;
logic exp_LINK_ready;
logic exp_adapter_rd_en;

function void build_expected();

logic sel_link;
logic sel_adapter;

sel_link    = LINK_vld;
sel_adapter = !LINK_vld && adapter_not_empty;

exp_msg   = sel_link ? LINK_msg : adapter_msg;
exp_valid = sel_link | sel_adapter ;

exp_LINK_ready    = mapper_ready && sel_link;
exp_adapter_rd_en = mapper_ready && sel_adapter;

endfunction

endclass
endpackage
