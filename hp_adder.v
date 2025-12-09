module hp_adder (
    input wire[15:0] hp_inA,
    input wire[15:0] hp_inB,
    output wire[15:0] hp_sum,
    output wire[1:0] Exceptions
);
    
    // declarations
    wire smaller, sign_a, sign_b, subtract_true, sign_similar, rest_similar;
    wire inf_true, inf_check_A, inf_check_B, nan_check_A, nan_check_B, nan_true;
    wire [4:0] exp_a, exp_b, exp_diff, larger_exp; 
    wire [12:0] mant_a, mant_b, shift_in, shift_out_at, shift_out_bt, operand_a, operand_b;
    wire [13:0] ALU_out;
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

    wire both_inf;
    wire inf_add_invalid;
    wire res_inf;
    wire comp_2_a, comp_2_b;
    
    // splitting 16-bit input into relevant fields
    assign a = hp_inA;
    assign b = hp_inB;
    assign exp_a = a[14:10];
    assign exp_b = b[14:10];

    // mantissa with implicit leading 1 for nonzero patterns 
    assign mant_a = ~&(a[14:0] || 15'b0) ? {a[9:0], 3'b0} : {1'b1, a[9:0], 2'b0};
    assign mant_b = ~&(b[14:0] || 15'b0) ? {b[9:0], 3'b0} : {1'b1, b[9:0], 2'b0};

    assign sign_a = a[15];
    assign sign_b = b[15];

    assign similar      = a[14:0]^b[14:0];
    assign rest_similar = |similar;
    assign sign_similar = ~(a[15]^b[15]);

    // basic special-case detection
    assign inf_check_A = (&a[14:10] && ~|a[9:0]);
    assign inf_check_B = (&b[14:10] && ~|b[9:0]);
    assign nan_check_A = (&a[14:10] && |a[9:0]);
    assign nan_check_B = (&b[14:10] && |b[9:0]);
    assign inf_true    = inf_check_A | inf_check_B;

    // +inf + -inf (or -inf + +inf) → invalid → NaN
    assign both_inf        = inf_check_A & inf_check_B;
    assign inf_add_invalid = both_inf & (sign_a ^ sign_b);

    // NaN if any input NaN or inf − inf
    assign nan_true = nan_check_A | nan_check_B | inf_add_invalid;

    // sign / exponent alignment
    always @(*) begin
        if (exp_a < exp_b) begin
            shifting_value = exp_b - exp_a;
            sign_fin       = sign_b;
        end
        else if (exp_a > exp_b) begin
            shifting_value = exp_a - exp_b;
            sign_fin       = sign_a;
        end
        else begin
            shifting_value = exp_a - exp_b;
            mant_diff      = mant_a - mant_b;
            sign_fin       = mant_diff[12] ? sign_b : sign_a;
        end
    end

    assign exp_diff = exp_a - exp_b;            
    assign smaller = ~exp_diff[4];        

    mux21_10 ma(.a(mant_a), .b(mant_b), .sel(smaller),     .out(shift_in));
    barrel_shifter b1(.in(shift_in), .shift_val(shifting_value), .out(shift_out_at));
    mux21_10 mb(.a(mant_a), .b(mant_b), .sel(~smaller),    .out(shift_out_bt));

    assign subtract_true = sign_a ^ sign_b;
    assign comp_2_a      = subtract_true & sign_a;
    assign comp_2_b      = subtract_true & sign_b;

    assign operand_a = comp_2_a ? (~shift_out_at  + 13'b1) : shift_out_at;
    assign operand_b = comp_2_b ? (~shift_out_bt  + 13'b1) : shift_out_bt;
    assign ALU_out   = operand_a + operand_b;
    
    /*
     * Renormalization and exponent calculation
     */

    mux21_5 mexp(.a(exp_a), .b(exp_b), .sel(~smaller), .out(larger_exp));

    always @(*) begin
        amount_shifted = 5'b0;
        exp_fin        = 6'b0;
        exp_fin        = larger_exp;

        if (!subtract_true & !inf_true) begin
            // addition path
            if (ALU_out[1:0] > 2'b01)
                mant_fin = ALU_out[11:0] + 10'b1;
            else
                mant_fin = ALU_out[11:0];

            if (ALU_out[13] == 1'b1) begin
                if (ALU_out[2:0] > 3'b011)
                    mant_fin = ALU_out[12:1] + 10'b1;
                else
                    mant_fin = ALU_out[12:1];
                    
                amount_shifted = 5'b1;
                exp_fin = (&(larger_exp & 5'b11111)) ? larger_exp : (larger_exp + 5'b00001);
            end

        end
        else if (subtract_true & !inf_true) begin
            // subtraction path
            if (~(rest_similar || sign_similar)) begin
                amount_shifted = 5'd0;
                mant_fin       = 12'b0;
                exp_fin        = 5'b0;
            end
            else begin
                /*
                 * Leading Zero Calculator
                 */
                casex (ALU_out[12:2])
                    {1'b1,           10'bx} : amount_shifted = -5'd0;
                    {1'b0, 1'b1,      9'bx} : amount_shifted = -5'd1;
                    {2'b0, 1'b1,      8'bx} : amount_shifted = -5'd2;
                    {3'b0, 1'b1,      7'bx} : amount_shifted = -5'd3;
                    {4'b0, 1'b1,      6'bx} : amount_shifted = -5'd4;
                    {5'b0, 1'b1,      5'bx} : amount_shifted = -5'd5;
                    {6'b0, 1'b1,      4'bx} : amount_shifted = -5'd6;
                    {7'b0, 1'b1,      3'bx} : amount_shifted = -5'd7;
                    {8'b0, 1'b1,      2'bx} : amount_shifted = -5'd8;
                    {9'b0, 1'b1,      1'bx} : amount_shifted = -5'd9;
                    {10'b0, 1'b1}           : amount_shifted = -5'd10;
                    default                 : amount_shifted = -5'd0;
                endcase
                temp     = (ALU_out << -amount_shifted);
                mant_fin = temp[11:0];
                exp_fin  = larger_exp + amount_shifted;
            end
        end
        else begin
            // inf path (when inf_true)
            exp_fin = 6'b011111;
        end
    end

    // simple rounding
    assign mant_out = mant_fin[1] ? (mant_fin[11:2] + 1'b1) : mant_fin[11:2];

    // result is infinity if exponent all ones and not flagged as NaN
    assign res_inf = (&exp_fin[4:0]) & ~nan_true;

    // underflow/overflow via exponent sign 
    assign flow_check = (~amount_shifted[4] & exp_fin[5]);

    assign hp_sum =
        nan_true ? 16'b1111111111111111 :
        (&exp_fin[4:0] ? {sign_fin, exp_fin[4:0], 10'b0}
                       : {sign_fin, exp_fin[4:0], mant_out});

    // Exceptions: NaN > inf > finite under/overflow > normal
    assign Exceptions =
        nan_true   ? 2'b11 :
        res_inf    ? (sign_fin ? 2'b10 : 2'b01) :
        flow_check ? (sign_fin ? 2'b10 : 2'b01) :
                     2'b00;

endmodule


// Separate non-parameterized muxes for sanity
module mux21_10(
    input wire[12:0] a,
    input wire[12:0] b,
    input wire sel,
    output reg[12:0] out
);
    always @(*) begin
        case (sel)
            1'b0: out = a;
            1'b1: out = b;
            default: out = 13'b0;
        endcase
    end
endmodule


module barrel_shifter (
    input  wire[12:0] in,
    input  wire[4:0]  shift_val,
    output wire[12:0] out
);      
    wire [12:0] num = in; 
    reg  [12:0] X, Y, Z, W, Dout;

    always @(*) begin
        /*
         * num -> X -> Y -> Z -> W -> Dout
         * bit 0 of shift_val: 0/1-bit shift
         * bit 1: 0/2-bit shift
         * bit 2: 0/4-bit shift
         * bit 3: 0/8-bit shift
         * bit 4: kill (shift >= 16 -> 0)
         */
        X    = shift_val[0] ? {1'b0, num[12:1]} : num[12:0];
        Y    = shift_val[1] ? {2'b0, X[12:2]}   : X[12:0];
        Z    = shift_val[2] ? {4'b0, Y[12:4]}   : Y[12:0];
        W    = shift_val[3] ? {8'b0, Z[12:8]}   : Z[12:0];
        Dout = shift_val[4] ? 13'b0            : W[12:0];
    end

    assign out = Dout;
endmodule


module mux21_5(
    input  wire[4:0] a,
    input  wire[4:0] b,
    input  wire sel,
    output reg [4:0] out
);
    always @(*) begin
        case (sel)
            1'b0: out = a;
            1'b1: out = b;
            default: out = 5'b0;
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
