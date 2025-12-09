module hp_multiplier(
    input [15:0] hp_inA,
    input [15:0] hp_inB,
    output [15:0] hp_product,
    output [1:0] Exceptions
);
    wire [9:0] mant_a, mant_b, mant_fin;
    reg [1:0] flag;
    wire [10:0] mult_in1, mult_in2;
    wire [12:0] mant_booth;
    wire [4:0] exp_a, exp_b;
    wire [5:0] exp_fin;
    wire [1:0] exp_inc;
    wire sign_fin, zero_a, zero_b, zero_true, inf_a, inf_b, inf_true, nan_a, nan_b, nan_true;
    wire [15:0] a,b;
    assign a = hp_inA;
    assign b = hp_inB;
    assign mant_a = a[9:0];
    assign mant_b = b[9:0];
    assign mult_in1 = {1'b1, mant_a};
    assign mult_in2 = {1'b1, mant_b};
    assign exp_a = a[14:10];
    assign exp_b = b[14:10];
    assign sign_a = a[15];
    assign sign_b = b[15];
    assign zero_a = ~|a[14:0];
    assign zero_b = ~|b[14:0];
    assign inf_a = &a[14:10] & ~|a[9:0];
    assign inf_b = &b[14:10] & ~|b[9:0];
    assign nan_a = &a[14:10] & |a[9:0];
    assign nan_b = &b[14:10] & |b[9:0];
    assign inf_true = inf_a | inf_b;
    assign zero_true = zero_a | zero_b;
    assign nan_true = nan_a | nan_b | (inf_true & zero_true);
    radix4_booth_multiplier mult1(.a(mult_in1), .num2(mult_in2), .out(mant_booth));

    assign exp_inc = (mant_booth[12])  ? 1'b1 : 1'b0;
    assign exp_fin = exp_a + exp_b + 5'b10001 + exp_inc;
    assign inf_fin = &exp_fin[4:0];
    assign sign_fin = sign_a ^ sign_b;
    assign Exceptions = nan_true ? (2'b11) : (inf_fin ? (sign_fin ? 2'b10 : 2'b01) : ((zero_true) ? 2'b00 : (exp_fin[5] ? (2'b00) : (sign_fin? 2'b10: 2'b01))));
    assign mant_fin = exp_inc ? (mant_booth[1] ? (mant_booth[11:2] + 1'b1) : mant_booth[11:2]) : (mant_booth[0] ? (mant_booth[10:1] + 1'b1) : mant_booth[10:1]); 
    assign hp_product = nan_true ? (16'b1111111111111111):(inf_true ? {sign_fin, 15'b111110000000000}:(zero_true? {sign_fin, 15'b000000000000000}: {sign_fin, exp_fin[4:0], mant_fin}));
endmodule




module partial_product_mux(
    input [10:0]num,
    input [2:0]sel,
    output [12:0]value
);
    wire [12:0] mc;
    assign mc = {num[10], num[10], num};
    reg [12:0] partial_product = 13'b0;
    reg [12:0] temp;
    wire [12:0] mc_2s, mc_2x, mc_2s_2x;
    assign mc_2s = ((~num) + 13'b1);
    assign mc_2s_2x = {mc_2s[11:0], 1'b0};
    assign mc_2x = {mc[11:0], 1'b0};
    always @ (*) begin
        case (sel)
          3'b001 : partial_product = num;
          3'b010 : partial_product = num;
          3'b011 : begin partial_product = mc_2x; partial_product[12] = 1'b0; end
          3'b100 : partial_product = mc_2s_2x;
          3'b101 : partial_product = mc_2s;
          3'b110 : partial_product = mc_2s;
          default: partial_product = 13'b0;
        endcase
    end
    assign value = partial_product;
endmodule




module radix4_booth_multiplier(
    input unsigned [10:0]a,
    input unsigned [10:0]num2,
    output [12:0] out
);

    wire unsigned [12:0] b;
    wire unsigned [21:0] product, product2;
    wire signed [12:0] pp1, pp2, pp3, pp4, pp5, pp6;
    wire signed [23:0] p1, p2, p3, p4, p5, p6;
    wire [2:0] pp1_sel, pp2_sel, pp3_sel, pp4_sel, pp5_sel, pp6_sel;

    //LSB Pad with zero and splitting done into 6 sets of 3 bits each which will be sent as select values.
    assign b = {1'b0, num2, 1'b0};
    assign pp1_sel = b[2:0];    
    assign pp2_sel = b[4:2];    
    assign pp3_sel = b[6:4];    
    assign pp4_sel = b[8:6];    
    assign pp5_sel = b[10:8];
    assign pp6_sel = b[12:10];
    
    //Partial products computed here.
    partial_product_mux pm1(.num(a), .sel(pp1_sel), .value(pp1));
    partial_product_mux pm2(.num(a), .sel(pp2_sel), .value(pp2));
    partial_product_mux pm3(.num(a), .sel(pp3_sel), .value(pp3));
    partial_product_mux pm4(.num(a), .sel(pp4_sel), .value(pp4));
    partial_product_mux pm5(.num(a), .sel(pp5_sel), .value(pp5));
    partial_product_mux pm6(.num(a), .sel(pp6_sel), .value(pp6));
    
    //Shifting along with addition completed here. 
    assign p1 = {{11{pp1[12]}}, pp1};
    assign p2 = {{9{pp2[12]}}, pp2, 2'b0};
    assign p3 = {{7{pp3[12]}}, pp3, 4'b0};
    assign p4 = {{5{pp4[12]}}, pp4, 6'b0};
    assign p5 = {{3{pp5[12]}}, pp5, 8'b0};
    assign p6 = {pp6[12], pp6, 10'b0};
    assign product = (p1 + p2 + p3 + p4 + p5 + p6); 
    assign out = product[21:9];
endmodule




module test_bench();
  reg [15:0] a;
  reg [15:0] b;
  wire [15:0] out;
  reg [15:0] expected_output;
  reg [10:0] expected_mantissa;
  reg [23:0] booth_out;
  wire [1:0] flag;
  hp_multiplier mult1(.hp_inA(a), .hp_inB(b), .hp_product(out), .Exceptions(flag));
initial 
  begin
    /* $monitor("InA = %b InB = %b,\nOutput = %b, Flag = %b\n\n\n", a, b, out, flag); */
    $monitor("InA = %b InB = %b,\n Expected = %b \nOutput = %b, Flag = %b\n\n\n", a, b, expected_output, out, flag);

    
    a = 16'b0110001011100101;
    b = 16'b0111111000111101;
    expected_output = 16'b1111111111111111; //NaN
    #100
    
    a = 16'b0111101101010100;
    b = 16'b0000100001100011; 
    expected_output = 16'b0100100000000101;
    #100

    a = 16'b0000000000000000;
    b = 16'b1101101010001010;
    expected_output = 16'b1000000000000000;
    #100
    
    a = 16'b0100000111010111;
    b = 16'b0100001111101100;
    expected_output = 16'b0100100111001000;
    #100

    a = 16'b0101101011100111; //220.9
    b = 16'b1100001111101100; //-3.96
    expected_output = 16'b1110001011010110;
    #100
    
    a = 16'b0111100101110000; //4.454E4
    b = 16'b0011110011110001; //1.235
    expected_output = 16'b0111101010111000;
    #100
    
    a = 16'b0111101101010100;
    b = 16'b0111100001100011;
    expected_output = 16'b0000100001010000; //Overflow
    #100

    
    a = 16'b0011110000001010; //1.01
    b = 16'b0011111101100110; //1.85
    expected_output = 16'b0011111101111000;
    #100
    
    a = 16'b0100010111111000; //5.97
    b = 16'b0100100011100110; //9.8
    expected_output = 16'b0101001101001111;
    #100
    
    a = 16'b1111101101010100;
    b = 16'b0111100001100011;
    expected_output = 16'b0000100001010000; //Overflow
    #100

    
    a = 16'b1011111011001101; //-1.7
    b = 16'b0100100011100110; //9.8
    expected_output = 16'b1100110000101010;
    #100
    
    a = 16'b1001011000100101; //-0.0015
    b = 16'b0110010011100110; //1254.0
    expected_output = 16'b1011111110000110;  
    #100

    a = 16'b0000000000000000;
    b = 16'b1101101010001010;
    expected_output = 16'b1000000000000000;
    #100
    
    a = 16'b1111101011100101;
    b = 16'b0011111000111101;
    expected_output = 16'b0000000000000001; //Underflow
    #100
    
    a = 16'b1000000000000000;
    b = 16'b1101101010001010;
    expected_output = 16'b0000000000000000;
    #100
    
    b = 16'b0000000000000000;
    a = 16'b1101101010001010;
    expected_output = 16'b1000000000000000;
    #100

    a = 16'b0111110000000000; //Inf
    b = 16'b1111111111111111; //NaN
    expected_output = 16'b1111111111111111; //Nan
    #100

    #100
    a = 16'b0111110000000000; //Inf
    b = 16'b1111110000000000; //-Inf
    expected_output = 16'b1111110000000000; //-Inf


    #100
    a = 16'b1111110000000000; //-Inf
    b = 16'b0000000000000000; // 0
    expected_output = 16'b1111111111111111; //Nan 

    #100
    a = 16'b0111110000000000; //Inf
    b = 16'b0111110000000000; //-Inf
    expected_output = 16'b0111110000000000; //-Inf

    #100
    a = 16'b1111111111111111; // NaN
    b = 16'b0000000000000000; // 0
    expected_output = 16'b1111111111111111; //NaN   
 end
endmodule
