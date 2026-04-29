interface sb_demapper_if(input bit clk);

    logic rst_n;
    
    // --- Inputs from SerDes ---
    logic [63:0]  msg_rcvd;      // Data captured from SerDes
    logic         msg_vld_rcvd;  // Valid signal from SerDes

    // --- Outputs to Demux (Router) ---
    logic [127:0] msg_word_rcvd; // Reconstructed 64-bit or 128-bit message
    logic         word_vld_rcvd; //

endinterface