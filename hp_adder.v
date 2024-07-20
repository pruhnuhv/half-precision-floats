module hp_adder (
    input wire[15:0] hp_inA,
    input wire[15:0] hp_inB,
    output wire[15:0] hp_sum,
    output wire[1:0] Exceptions
);
    
    //declarations
    
    wire smaller, sign_a, sign_b, subtract_true, sign_similar, rest_similar, inf_true, inf_check_A, inf_check_B, nan_check_A, nan_check_B, nan_true;
    wire [4:0] exp_a, exp_b, exp_diff, larger_exp; 
    wire [12:0] mant_a, mant_b, shift_in, shift_out_a, shift_out_b, shift_out_at, shift_out_bt, operand_a, operand_b;
    wire [13:0] asumb, adiffb, ALU_out;
    wire [14:0] similar;
   
    reg done = 1'b0, sign_fin, zero = 1'b0;
    wire flow_check;
    reg [1:0] flag = 2'b00;
    reg [4:0] amount_shifted = 5'd0, shifting_value;
    reg [5:0] exp_fin;
    reg [11:0] mant_fin = 12'b0;
    wire [9:0] mant_out;
    reg [12:0] mant_diff;
    reg [13:0] temp;
    wire [15:0] a,b;
    
    //splitting 16 - bit input into relavent information
    assign a = hp_inA;
    assign b = hp_inB;
    assign exp_a = a[14:10];
    assign exp_b = b[14:10];
    assign mant_a = ~&(a[14:0] || 15'b0) ? {a[9:0], 3'b0} : {1'b1, a[9:0], 2'b0};
    assign mant_b = ~&(b[14:0] || 15'b0) ? {b[9:0], 3'b0} : {1'b1, b[9:0], 2'b0};
    assign sign_a = a[15];
    assign sign_b = b[15];
    assign similar = a[14:0]^b[14:0];
    assign rest_similar = |similar;
    assign sign_similar = ~(a[15]^b[15]);
    assign inf_check_A = (&a[14:10] && ~|a[9:0]);
    assign inf_check_B = (&b[14:10] && ~|b[9:0]);
    assign nan_check_A = (&a[14:10] && |a[9:0]);
    assign nan_check_B = (&b[14:10] && |b[9:0]);
    assign nan_true = nan_check_A | nan_check_B;
    assign inf_true = inf_check_A | inf_check_B;

    always @(*) begin
        if(exp_a < exp_b)
        begin
            shifting_value = exp_b - exp_a;
            sign_fin = sign_b;
        end
        else if(exp_a > exp_b)
        begin
            shifting_value = exp_a - exp_b;
            sign_fin = sign_a;
        end
        else
        begin
                shifting_value = exp_a - exp_b;
                mant_diff = mant_a - mant_b;
                sign_fin = mant_diff[11]? sign_b: sign_a;
        end
    end

    assign exp_diff = exp_a - exp_b;            
    assign smaller = ~exp_diff[4];              
   
    mux21_10 ma(.a(mant_a), .b(mant_b), .sel(smaller), .out(shift_in));
    barrel_shifter b1(.in(shift_in), .shift_val(shifting_value), .out(shift_out_at));
    mux21_10 mb(.a(mant_a), .b(mant_b), .sel(~smaller), .out(shift_out_bt));

    /*
    ALU Operations (and corresponding shifts)
    */

    assign subtract_true = sign_a ^ sign_b;
    assign comp_2_a = subtract_true & sign_a;
    assign comp_2_b = subtract_true & sign_b;
    assign operand_a = (comp_2_a) ? (~(shift_out_at)+13'b1) : shift_out_at;
    assign operand_b = (comp_2_b) ? (~(shift_out_bt)+13'b1) : shift_out_bt;
    assign ALU_out = operand_a + operand_b;
    
   /*
   Renormalization And Exponent Calculation
   */

    mux21_5 mexp(.a(exp_a), .b(exp_b), .sel(~smaller), .out(larger_exp));
    always @(*) begin
        amount_shifted = 5'b0;
        exp_fin = 6'b0;
        exp_fin = larger_exp;
       if(!subtract_true & !inf_true) begin
            if(ALU_out[1:0] > 2'b01)
                mant_fin = ALU_out[11:0] + 10'b1;
            else
                mant_fin = ALU_out[11:0];

            if(ALU_out[13] == 1'b1) begin
                if(ALU_out[2:0] > 3'b011)
                    mant_fin = ALU_out[12:1] + 10'b1;
                else
                    mant_fin = ALU_out[12:1];
                    
                amount_shifted = 5'b1;
                exp_fin = (&(larger_exp & 5'b11111)) ? larger_exp : (larger_exp + 5'b00001);
            end

        end
        else if(subtract_true & !inf_true)begin
            if(~(rest_similar || sign_similar))
            begin
                amount_shifted = 5'd0;
                mant_fin = 12'b0;
                exp_fin = 5'b0;
            end
            else
            begin
                /*
                Leading Zero Calculator
                */
                casex(ALU_out[12:2])
                    {1'b1, 10'bx}         :begin  amount_shifted = -5'd0;   end
                    {1'b0, 1'b1, 9'bx}    :begin  amount_shifted = -5'd1;   end
                    {2'b0, 1'b1, 8'bx}    :begin  amount_shifted = -5'd2;   end
                    {3'b0, 1'b1, 7'bx}    :begin  amount_shifted = -5'd3;   end
                    {4'b0, 1'b1, 6'bx}    :begin  amount_shifted = -5'd4;   end
                    {5'b0, 1'b1, 5'bx}    :begin  amount_shifted = -5'd5;   end
                    {6'b0, 1'b1, 4'bx}    :begin  amount_shifted = -5'd6;   end
                    {7'b0, 1'b1, 3'bx}    :begin  amount_shifted = -5'd7;   end
                    {8'b0, 1'b1, 2'bx}    :begin  amount_shifted = -5'd8;   end
                    {9'b0, 1'b1, 1'bx}    :begin  amount_shifted = -5'd9;   end
                    {10'b0, 1'b1}         :begin  amount_shifted = -5'd10;  end
                    default               :begin  amount_shifted = -5'd0;   end
                endcase
                temp = (ALU_out << -amount_shifted);
                mant_fin = temp[11:0];
                exp_fin = larger_exp + amount_shifted;
            end
        end
        else
        begin
            exp_fin = 6'b011111;
        end
    end
    assign mant_out = mant_fin[1] ? (mant_fin[11:2]+1'b1) : mant_fin[11:2];
    assign hp_sum = nan_true? 16'b1111111111111111 : (&exp_fin[4:0] ? {sign_fin, exp_fin[4:0], 10'b0}: ({sign_fin, exp_fin[4:0], mant_out}));
    assign flow_check = (~amount_shifted[4] & exp_fin[5]) | &exp_fin[4:0];
    assign Exceptions = nan_true ? (2'b11) : inf_true ? (2'b00) : (flow_check ? (sign_fin ? 2'b10 : 2'b01 ): 2'b00);
endmodule


//Separate non-parameterized muxes for sanity
module mux21_10(
    input wire[12:0] a,
    input wire[12:0] b,
    input wire sel,
    output reg[12:0] out
);
    /* 2:1 Mux with 10 bits as each input and 1 bit select*/
    always@ (*)
        begin
            case(sel)
            1'b0: out = a;
            1'b1: out = b;
            default: out = 0;
            endcase
        end

endmodule



module barrel_shifter (
    input wire[12:0] in,
    input wire[4:0] shift_val,
    output wire[12:0] out);      
    wire [12:0] num = in; 
    reg [12:0] X, Y, Z, W, Dout;

    always @ (*)
      begin
        
      /*  
        num -> X -> Y -> Z -> W -> Dout
        Where num->X would be a 0 or 1 bit shift, X->Y would be a 0 or 2 bit shift, 
        Y->Z would be a 0 or 4 bit shift and Z->Dout would be a 0 or 8 bit shift.
        Each of these 0 or 2^n shift would be as per the n'th bit of shift_val
      */

      X = shift_val[0] ? {1'b0, num[12:1]} : num[12:0];
      Y = shift_val[1] ? {2'b0, X[12:2]} : X[12:0];
      Z = shift_val[2] ? {4'b0, Y[12:4]} : Y[12:0];
      W = shift_val[3] ? {8'b0, Z[12:8]} : Z[12:0];
      Dout = shift_val[4] ? 13'b0 : W[12:0];
      
    end
    assign out = Dout;
endmodule



module mux21_5(
    input wire[4:0] a,
    input wire[4:0] b,
    input wire sel,
    output reg[4:0] out
);
    /* 2:1 Mux with 5 bits as each input and 1 bit select*/
    always@ (*)
        begin
            case(sel)
            1'b0: out = a;
            1'b1: out = b;
            default: out = 0;
            endcase
        end
endmodule


module test_bench ();
    reg [15:0] num1;
    reg [15:0] num2;
    reg [9:0] expected;
    wire [15:0] total;
    wire [1:0] op_flags;
    reg [15:0] exp_sum;
    hp_adder fp_adder(.hp_inA(num1), .hp_inB(num2), .hp_sum(total), .Exceptions(op_flags));
    initial 
    begin
        $monitor("In1 =  %b In2 = %b\nOutput = %b Exceptions = %b\nExpect = %b\n\n", num1, num2, total, op_flags, exp_sum);
        
        num1 = 16'b1111011110010100;    //-3.104E4
        num2 = 16'b1111101100101010;    //-5.87E4
        exp_sum = 16'b1111110000000000; //-inf :  Set Underflow flag
        
        #50
        num1 = 16'b0111011110010100;    //3.104E4
        num2 = 16'b0111101100101010;    //5.87E4
        exp_sum = 16'b0111110000000000; //inf :  Set Overflow flag
        
        #50 
        num1 = 16'b0100101000100001;    //12.26
        num2 = 16'b1100101000100001;    //-12.26
        exp_sum = 16'b0000000000000000; //0
        
        #50
        num1 = 16'b1111011110010100;    //-3.104E4
        num2 = 16'b1111111100101010;    //NaN
        exp_sum = 16'b1111111111111111; //NaN
        
        #50
        num1 = 16'b0111110000000000;    //+inf
        num2 = 16'b0111110000000000;    //+inf
        exp_sum = 16'b0111110000000000; //+inf : set others flag (infinity case)
        
        #50
        num1 = 16'b1111011110010100;    //-3.104E4
        num2 = 16'b1110110110111100;    //-5.87E3
        exp_sum = 16'b1111100010000010; //-3.693E4
        
        #50
        num1 = 16'b0111011110010100;    //3.104E4
        num2 = 16'b0110110110111100;    //5.87E3
        exp_sum = 16'b0111100010000010; //3.693E4
        
        #50
        num1 = 16'b1100101110000000;    //0
        num2 = 16'b1101010101111010;    //0
        exp_sum = 16'b1101011001101010;
        
        #50
        num1 = 16'b0000000000000000;    //0
        num2 = 16'b0000000000000000;    //0
        exp_sum = 16'b0000000000000000;

        #50
        num1 = 16'b0100101000100001;    //12.26
        num2 = 16'b1111110000000000;    //-inf
        exp_sum = 16'b1111110000000000; //+inf
        
        #50
        num1 = 16'b0111110000000000;    //+inf
        num2 = 16'b1111110000000000;    //-inf
        exp_sum = 16'b0111110000000000; //+inf
        
        #50
        num1 = 16'b0100101000100001;    //12.26
        num2 = 16'b0111110000000000;    //+inf
        exp_sum = 16'b0111110000000000; //+inf
        
        
        #50
        num1 = 16'b0100101000100001;    //12.26
        num2 = 16'b0100000000000000;     //2.0
        exp_sum = 16'b0100101100100001; //2.0
        
        #50
        num1 = 16'b0100101000100001;    //12.26
        num2 = 16'b0011110000000000;    //1
        exp_sum = 16'b0100101010100001; //13.26

        #50
        num1 = 16'b1100000010011010;    //-2.3
        num2 = 16'b0100010001001101;    //4.3
        exp_sum = 16'b0100000000000000; //2.0
        
        #50
        num1 = 16'b0100101000100001;    //12.26
        num2 = 16'b0101010001011011;    //69.7
        exp_sum = 16'b0101010100011111; //81.94
        

        #50
        num1 = 16'b0101010110100110;    //90.4
        num2 = 16'b0101000100100110;    //41.2
        exp_sum = 16'b0101100000011101;
        
        #50        
        num1 = 16'b0101000001110011;    //35.6
        num2 = 16'b0101000100100110;    //41.2
        exp_sum = 16'b0101010011001101;

        #50
        num1 = 16'b0011100011001101;    //0.6
        num2 = 16'b0101000100100110;    //41.2
        exp_sum = 16'b0101000100111001;

        #50        
        num1 = 16'b1101010110100110;    //-90.4
        num2 = 16'b0101000100100110;    //41.2
        exp_sum = 16'b1101001000100110;

        #50
        num1 = 16'b0101000001110011;    //35.6
        num2 = 16'b1101000100100110;    //-41.2
        exp_sum = 16'b1100010110011000;
        
        #50
        num2 = 16'b1101000001110011;    //-35.6
        num1 = 16'b1101000100100110;    //-41.2
        exp_sum = 16'b1101010011001101;
    end
endmodule
