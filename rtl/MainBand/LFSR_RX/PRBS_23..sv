module 
function [31:0] prbs23_custom;
    input [31:0] in;
    reg fb0, fb1, fb2, fb3, fb4, fb5, fb6, fb7,
        fb8, fb9, fb10, fb11, fb12, fb13, fb14, fb15,
        fb16, fb17, fb18, fb19, fb20, fb21, fb22, fb23,
        fb24, fb25, fb26, fb27, fb28, fb29, fb30, fb31;
    begin
       
        fb0  = in[22]^in[20]^in[15]^in[ 7]^in[ 4]^in[ 1];
        fb1  = in[21]^in[19]^in[14]^in[ 6]^in[ 3]^in[ 0];
        fb2  = in[20]^in[18]^in[13]^in[ 5]^in[ 2]^fb0;
        fb3  = in[19]^in[17]^in[12]^in[ 4]^in[ 1]^fb1;
        fb4  = in[18]^in[16]^in[11]^in[ 3]^in[ 0]^fb2;
        fb5  = in[17]^in[15]^in[10]^in[ 2]^fb0    ^fb3;
        fb6  = in[16]^in[14]^in[ 9]^in[ 1]^fb1    ^fb4;
        fb7  = in[15]^in[13]^in[ 8]^in[ 0]^fb2    ^fb5;
        fb8  = in[14]^in[12]^in[ 7]^fb0   ^fb3    ^fb6;
        fb9  = in[13]^in[11]^in[ 6]^fb1   ^fb4    ^fb7;
        fb10 = in[12]^in[10]^in[ 5]^fb2   ^fb5    ^fb8;
        fb11 = in[11]^in[ 9]^in[ 4]^fb3   ^fb6    ^fb9;
        fb12 = in[10]^in[ 8]^in[ 3]^fb4   ^fb7    ^fb10;
        fb13 = in[ 9]^in[ 7]^in[ 2]^fb5   ^fb8    ^fb11;
        fb14 = in[ 8]^in[ 6]^in[ 1]^fb6   ^fb9    ^fb12;
        fb15 = in[ 7]^in[ 5]^in[ 0]^fb7   ^fb10   ^fb13;
        fb16 = in[ 6]^in[ 4]^fb0   ^fb8   ^fb11   ^fb14;
        fb17 = in[ 5]^in[ 3]^fb1   ^fb9   ^fb12   ^fb15;
        fb18 = in[ 4]^in[ 2]^fb2   ^fb10  ^fb13   ^fb16;
        fb19 = in[ 3]^in[ 1]^fb3   ^fb11  ^fb14   ^fb17;
        fb20 = in[ 2]^in[ 0]^fb4   ^fb12  ^fb15   ^fb18;
        fb21 = in[ 1]^fb0   ^fb5   ^fb13  ^fb16   ^fb19;
        fb22 = in[ 0]^fb1   ^fb6   ^fb14  ^fb17   ^fb20;
        fb23 = fb0  ^fb2    ^fb7   ^fb15  ^fb18   ^fb21;
        fb24 = fb1  ^fb3    ^fb8   ^fb16  ^fb19   ^fb22;
        fb25 = fb2  ^fb4    ^fb9   ^fb17  ^fb20   ^fb23;
        fb26 = fb3  ^fb5    ^fb10  ^fb18  ^fb21   ^fb24;
        fb27 = fb4  ^fb6    ^fb11  ^fb19  ^fb22   ^fb25;
        fb28 = fb5  ^fb7    ^fb12  ^fb20  ^fb23   ^fb26;
        fb29 = fb6  ^fb8    ^fb13  ^fb21  ^fb24   ^fb27;
        fb30 = fb7  ^fb9    ^fb14  ^fb22  ^fb25   ^fb28;
        fb31 = fb8  ^fb10   ^fb15  ^fb23  ^fb26   ^fb29;

        // الـ output بيتكتب من الـ MSB للـ LSB
        prbs23_custom[31] = fb31;
        prbs23_custom[30] = fb30;
        prbs23_custom[29] = fb29;
        prbs23_custom[28] = fb28;
        prbs23_custom[27] = fb27;
        prbs23_custom[26] = fb26;
        prbs23_custom[25] = fb25;
        prbs23_custom[24] = fb24;
        prbs23_custom[23] = fb23;
        prbs23_custom[22] = fb22;
        prbs23_custom[21] = fb21;
        prbs23_custom[20] = fb20;
        prbs23_custom[19] = fb19;
        prbs23_custom[18] = fb18;
        prbs23_custom[17] = fb17;
        prbs23_custom[16] = fb16;
        prbs23_custom[15] = fb15;
        prbs23_custom[14] = fb14;
        prbs23_custom[13] = fb13;
        prbs23_custom[12] = fb12;
        prbs23_custom[11] = fb11;
        prbs23_custom[10] = fb10;
        prbs23_custom[ 9] = fb9;
        prbs23_custom[ 8] = fb8;
        prbs23_custom[ 7] = fb7;
        prbs23_custom[ 6] = fb6;
        prbs23_custom[ 5] = fb5;
        prbs23_custom[ 4] = fb4;
        prbs23_custom[ 3] = fb3;
        prbs23_custom[ 2] = fb2;
        prbs23_custom[ 1] = fb1;
        prbs23_custom[ 0] = fb0;
    end
endfunction
endmodule