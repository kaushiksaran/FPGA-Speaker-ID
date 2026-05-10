`timescale 1ns / 1ps

// speaker_nn.v - 2-speaker NN inference engine for Artix-7 (XC7A35T)
// Architecture: Normalize(416) -> FC(416->16, ReLU) -> FC(16->2) -> logits
// Weights: INT16 (W_SCALE=1024), Inputs: INT8, MAC_SHIFT=10
// Timing: 417 (norm) + 16*417 (L1) + 2*17 (L2) + 1 (output) = 7,004 cycles
//         = ~70us at 100MHz

module speaker_nn (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [13311:0] mfcc_in_flat,
    output reg         valid,
    output reg  signed [31:0] logit0,
    output reg  signed [31:0] logit1
);

wire signed [31:0] mfcc_in [0:415];
genvar gi;
generate
    for (gi = 0; gi < 416; gi = gi + 1) begin
        assign mfcc_in[gi] = mfcc_in_flat[gi*32 +: 32];
    end
endgenerate

localparam N_IN       = 416;
localparam N_HID      = 16;
localparam MAC_SHIFT  = 10;
localparam NORM_SHIFT = 14;

localparam [2:0] S_IDLE   = 3'd0,
                 S_NORM   = 3'd1,
                 S_L1_MAC = 3'd2,
                 S_L1_WB  = 3'd3,
                 S_L2_MAC = 3'd4,
                 S_L2_WB  = 3'd5,
                 S_OUTPUT = 3'd6;

reg [2:0]  state;
reg [8:0]  idx;
reg [4:0]  neuron;

reg signed [7:0]  x_norm [0:415];
reg signed [31:0] l1_out [0:15];
reg signed [31:0] acc;

reg signed [31:0] norm_diff_r;
reg [8:0]         norm_idx_r;

wire signed [41:0] norm_prod    = norm_diff_r * $signed({1'b0, recip_rom[norm_idx_r]});
wire signed [31:0] norm_shifted = norm_prod >>> NORM_SHIFT;
wire signed [7:0]  norm_clipped = (norm_shifted > 32'sd127)  ?  8'sd127 :
                                  (norm_shifted < -32'sd128) ? -8'sd128 :
                                  norm_shifted[7:0];

(* ram_style = "block" *) reg signed [15:0] w1_rom [0:6655];
(* rom_style = "distributed" *) reg signed [15:0] w2_rom [0:31];

initial begin
    $readmemh("C:/Users/HP/Desktop/speaker_id_w1_new.hex", w1_rom);
    $readmemh("C:/Users/HP/Desktop/speaker_id_w2_new.hex", w2_rom);
end

reg [12:0] w1_base;
wire [12:0] w1_addr = w1_base + {4'd0, idx};
wire signed [15:0] w1_val = w1_rom[w1_addr];

wire [4:0] w2_addr = {neuron[0], idx[3:0]};
wire signed [15:0] w2_val = w2_rom[w2_addr];

(* rom_style = "block" *) reg signed [31:0] x_mean_rom [0:415];
initial begin
    x_mean_rom[  0] = 32'sh0004C3B0;
    x_mean_rom[  1] = 32'sh00045FF6;
    x_mean_rom[  2] = 32'sh00035142;
    x_mean_rom[  3] = 32'sh0001E4E5;
    x_mean_rom[  4] = 32'sh00007DA1;
    x_mean_rom[  5] = 32'shFFFF7375;
    x_mean_rom[  6] = 32'shFFFEF803;
    x_mean_rom[  7] = 32'shFFFF0A45;
    x_mean_rom[  8] = 32'shFFFF7CEC;
    x_mean_rom[  9] = 32'sh00000B85;
    x_mean_rom[ 10] = 32'sh000075EB;
    x_mean_rom[ 11] = 32'sh000096D2;
    x_mean_rom[ 12] = 32'sh00006DA9;
    x_mean_rom[ 13] = 32'sh0004C3B0;
    x_mean_rom[ 14] = 32'sh00045FF6;
    x_mean_rom[ 15] = 32'sh00035142;
    x_mean_rom[ 16] = 32'sh0001E4E5;
    x_mean_rom[ 17] = 32'sh00007DA1;
    x_mean_rom[ 18] = 32'shFFFF7375;
    x_mean_rom[ 19] = 32'shFFFEF803;
    x_mean_rom[ 20] = 32'shFFFF0A45;
    x_mean_rom[ 21] = 32'shFFFF7CEC;
    x_mean_rom[ 22] = 32'sh00000B85;
    x_mean_rom[ 23] = 32'sh000075EB;
    x_mean_rom[ 24] = 32'sh000096D2;
    x_mean_rom[ 25] = 32'sh00006DA9;
    x_mean_rom[ 26] = 32'sh0004C3B0;
    x_mean_rom[ 27] = 32'sh00045FF6;
    x_mean_rom[ 28] = 32'sh00035142;
    x_mean_rom[ 29] = 32'sh0001E4E5;
    x_mean_rom[ 30] = 32'sh00007DA1;
    x_mean_rom[ 31] = 32'shFFFF7375;
    x_mean_rom[ 32] = 32'shFFFEF803;
    x_mean_rom[ 33] = 32'shFFFF0A45;
    x_mean_rom[ 34] = 32'shFFFF7CEC;
    x_mean_rom[ 35] = 32'sh00000B85;
    x_mean_rom[ 36] = 32'sh000075EB;
    x_mean_rom[ 37] = 32'sh000096D2;
    x_mean_rom[ 38] = 32'sh00006DA9;
    x_mean_rom[ 39] = 32'sh0004C3B0;
    x_mean_rom[ 40] = 32'sh00045FF6;
    x_mean_rom[ 41] = 32'sh00035142;
    x_mean_rom[ 42] = 32'sh0001E4E5;
    x_mean_rom[ 43] = 32'sh00007DA1;
    x_mean_rom[ 44] = 32'shFFFF7375;
    x_mean_rom[ 45] = 32'shFFFEF803;
    x_mean_rom[ 46] = 32'shFFFF0A45;
    x_mean_rom[ 47] = 32'shFFFF7CEC;
    x_mean_rom[ 48] = 32'sh00000B85;
    x_mean_rom[ 49] = 32'sh000075EB;
    x_mean_rom[ 50] = 32'sh000096D2;
    x_mean_rom[ 51] = 32'sh00006DA9;
    x_mean_rom[ 52] = 32'sh0004C3B0;
    x_mean_rom[ 53] = 32'sh00045FF6;
    x_mean_rom[ 54] = 32'sh00035142;
    x_mean_rom[ 55] = 32'sh0001E4E5;
    x_mean_rom[ 56] = 32'sh00007DA1;
    x_mean_rom[ 57] = 32'shFFFF7375;
    x_mean_rom[ 58] = 32'shFFFEF803;
    x_mean_rom[ 59] = 32'shFFFF0A45;
    x_mean_rom[ 60] = 32'shFFFF7CEC;
    x_mean_rom[ 61] = 32'sh00000B85;
    x_mean_rom[ 62] = 32'sh000075EB;
    x_mean_rom[ 63] = 32'sh000096D2;
    x_mean_rom[ 64] = 32'sh00006DA9;
    x_mean_rom[ 65] = 32'sh0004C3B0;
    x_mean_rom[ 66] = 32'sh00045FF6;
    x_mean_rom[ 67] = 32'sh00035142;
    x_mean_rom[ 68] = 32'sh0001E4E5;
    x_mean_rom[ 69] = 32'sh00007DA1;
    x_mean_rom[ 70] = 32'shFFFF7375;
    x_mean_rom[ 71] = 32'shFFFEF803;
    x_mean_rom[ 72] = 32'shFFFF0A45;
    x_mean_rom[ 73] = 32'shFFFF7CEC;
    x_mean_rom[ 74] = 32'sh00000B85;
    x_mean_rom[ 75] = 32'sh000075EB;
    x_mean_rom[ 76] = 32'sh000096D2;
    x_mean_rom[ 77] = 32'sh00006DA9;
    x_mean_rom[ 78] = 32'sh0004C3B0;
    x_mean_rom[ 79] = 32'sh00045FF6;
    x_mean_rom[ 80] = 32'sh00035142;
    x_mean_rom[ 81] = 32'sh0001E4E5;
    x_mean_rom[ 82] = 32'sh00007DA1;
    x_mean_rom[ 83] = 32'shFFFF7375;
    x_mean_rom[ 84] = 32'shFFFEF803;
    x_mean_rom[ 85] = 32'shFFFF0A45;
    x_mean_rom[ 86] = 32'shFFFF7CEC;
    x_mean_rom[ 87] = 32'sh00000B85;
    x_mean_rom[ 88] = 32'sh000075EB;
    x_mean_rom[ 89] = 32'sh000096D2;
    x_mean_rom[ 90] = 32'sh00006DA9;
    x_mean_rom[ 91] = 32'sh0004C3B0;
    x_mean_rom[ 92] = 32'sh00045FF6;
    x_mean_rom[ 93] = 32'sh00035142;
    x_mean_rom[ 94] = 32'sh0001E4E5;
    x_mean_rom[ 95] = 32'sh00007DA1;
    x_mean_rom[ 96] = 32'shFFFF7375;
    x_mean_rom[ 97] = 32'shFFFEF803;
    x_mean_rom[ 98] = 32'shFFFF0A45;
    x_mean_rom[ 99] = 32'shFFFF7CEC;
    x_mean_rom[100] = 32'sh00000B85;
    x_mean_rom[101] = 32'sh000075EB;
    x_mean_rom[102] = 32'sh000096D2;
    x_mean_rom[103] = 32'sh00006DA9;
    x_mean_rom[104] = 32'sh0004C3B0;
    x_mean_rom[105] = 32'sh00045FF6;
    x_mean_rom[106] = 32'sh00035142;
    x_mean_rom[107] = 32'sh0001E4E5;
    x_mean_rom[108] = 32'sh00007DA1;
    x_mean_rom[109] = 32'shFFFF7375;
    x_mean_rom[110] = 32'shFFFEF803;
    x_mean_rom[111] = 32'shFFFF0A45;
    x_mean_rom[112] = 32'shFFFF7CEC;
    x_mean_rom[113] = 32'sh00000B85;
    x_mean_rom[114] = 32'sh000075EB;
    x_mean_rom[115] = 32'sh000096D2;
    x_mean_rom[116] = 32'sh00006DA9;
    x_mean_rom[117] = 32'sh0004C3B0;
    x_mean_rom[118] = 32'sh00045FF6;
    x_mean_rom[119] = 32'sh00035142;
    x_mean_rom[120] = 32'sh0001E4E5;
    x_mean_rom[121] = 32'sh00007DA1;
    x_mean_rom[122] = 32'shFFFF7375;
    x_mean_rom[123] = 32'shFFFEF803;
    x_mean_rom[124] = 32'shFFFF0A45;
    x_mean_rom[125] = 32'shFFFF7CEC;
    x_mean_rom[126] = 32'sh00000B85;
    x_mean_rom[127] = 32'sh000075EB;
    x_mean_rom[128] = 32'sh000096D2;
    x_mean_rom[129] = 32'sh00006DA9;
    x_mean_rom[130] = 32'sh0004C3B0;
    x_mean_rom[131] = 32'sh00045FF6;
    x_mean_rom[132] = 32'sh00035142;
    x_mean_rom[133] = 32'sh0001E4E5;
    x_mean_rom[134] = 32'sh00007DA1;
    x_mean_rom[135] = 32'shFFFF7375;
    x_mean_rom[136] = 32'shFFFEF803;
    x_mean_rom[137] = 32'shFFFF0A45;
    x_mean_rom[138] = 32'shFFFF7CEC;
    x_mean_rom[139] = 32'sh00000B85;
    x_mean_rom[140] = 32'sh000075EB;
    x_mean_rom[141] = 32'sh000096D2;
    x_mean_rom[142] = 32'sh00006DA9;
    x_mean_rom[143] = 32'sh0004C3B0;
    x_mean_rom[144] = 32'sh00045FF6;
    x_mean_rom[145] = 32'sh00035142;
    x_mean_rom[146] = 32'sh0001E4E5;
    x_mean_rom[147] = 32'sh00007DA1;
    x_mean_rom[148] = 32'shFFFF7375;
    x_mean_rom[149] = 32'shFFFEF803;
    x_mean_rom[150] = 32'shFFFF0A45;
    x_mean_rom[151] = 32'shFFFF7CEC;
    x_mean_rom[152] = 32'sh00000B85;
    x_mean_rom[153] = 32'sh000075EB;
    x_mean_rom[154] = 32'sh000096D2;
    x_mean_rom[155] = 32'sh00006DA9;
    x_mean_rom[156] = 32'sh0004C3B0;
    x_mean_rom[157] = 32'sh00045FF6;
    x_mean_rom[158] = 32'sh00035142;
    x_mean_rom[159] = 32'sh0001E4E5;
    x_mean_rom[160] = 32'sh00007DA1;
    x_mean_rom[161] = 32'shFFFF7375;
    x_mean_rom[162] = 32'shFFFEF803;
    x_mean_rom[163] = 32'shFFFF0A45;
    x_mean_rom[164] = 32'shFFFF7CEC;
    x_mean_rom[165] = 32'sh00000B85;
    x_mean_rom[166] = 32'sh000075EB;
    x_mean_rom[167] = 32'sh000096D2;
    x_mean_rom[168] = 32'sh00006DA9;
    x_mean_rom[169] = 32'sh0004C3B0;
    x_mean_rom[170] = 32'sh00045FF6;
    x_mean_rom[171] = 32'sh00035142;
    x_mean_rom[172] = 32'sh0001E4E5;
    x_mean_rom[173] = 32'sh00007DA1;
    x_mean_rom[174] = 32'shFFFF7375;
    x_mean_rom[175] = 32'shFFFEF803;
    x_mean_rom[176] = 32'shFFFF0A45;
    x_mean_rom[177] = 32'shFFFF7CEC;
    x_mean_rom[178] = 32'sh00000B85;
    x_mean_rom[179] = 32'sh000075EB;
    x_mean_rom[180] = 32'sh000096D2;
    x_mean_rom[181] = 32'sh00006DA9;
    x_mean_rom[182] = 32'sh0004C3B0;
    x_mean_rom[183] = 32'sh00045FF6;
    x_mean_rom[184] = 32'sh00035142;
    x_mean_rom[185] = 32'sh0001E4E5;
    x_mean_rom[186] = 32'sh00007DA1;
    x_mean_rom[187] = 32'shFFFF7375;
    x_mean_rom[188] = 32'shFFFEF803;
    x_mean_rom[189] = 32'shFFFF0A45;
    x_mean_rom[190] = 32'shFFFF7CEC;
    x_mean_rom[191] = 32'sh00000B85;
    x_mean_rom[192] = 32'sh000075EB;
    x_mean_rom[193] = 32'sh000096D2;
    x_mean_rom[194] = 32'sh00006DA9;
    x_mean_rom[195] = 32'sh0004C3B0;
    x_mean_rom[196] = 32'sh00045FF6;
    x_mean_rom[197] = 32'sh00035142;
    x_mean_rom[198] = 32'sh0001E4E5;
    x_mean_rom[199] = 32'sh00007DA1;
    x_mean_rom[200] = 32'shFFFF7375;
    x_mean_rom[201] = 32'shFFFEF803;
    x_mean_rom[202] = 32'shFFFF0A45;
    x_mean_rom[203] = 32'shFFFF7CEC;
    x_mean_rom[204] = 32'sh00000B85;
    x_mean_rom[205] = 32'sh000075EB;
    x_mean_rom[206] = 32'sh000096D2;
    x_mean_rom[207] = 32'sh00006DA9;
    x_mean_rom[208] = 32'sh0004C3B0;
    x_mean_rom[209] = 32'sh00045FF6;
    x_mean_rom[210] = 32'sh00035142;
    x_mean_rom[211] = 32'sh0001E4E5;
    x_mean_rom[212] = 32'sh00007DA1;
    x_mean_rom[213] = 32'shFFFF7375;
    x_mean_rom[214] = 32'shFFFEF803;
    x_mean_rom[215] = 32'shFFFF0A45;
    x_mean_rom[216] = 32'shFFFF7CEC;
    x_mean_rom[217] = 32'sh00000B85;
    x_mean_rom[218] = 32'sh000075EB;
    x_mean_rom[219] = 32'sh000096D2;
    x_mean_rom[220] = 32'sh00006DA9;
    x_mean_rom[221] = 32'sh0004C3B0;
    x_mean_rom[222] = 32'sh00045FF6;
    x_mean_rom[223] = 32'sh00035142;
    x_mean_rom[224] = 32'sh0001E4E5;
    x_mean_rom[225] = 32'sh00007DA1;
    x_mean_rom[226] = 32'shFFFF7375;
    x_mean_rom[227] = 32'shFFFEF803;
    x_mean_rom[228] = 32'shFFFF0A45;
    x_mean_rom[229] = 32'shFFFF7CEC;
    x_mean_rom[230] = 32'sh00000B85;
    x_mean_rom[231] = 32'sh000075EB;
    x_mean_rom[232] = 32'sh000096D2;
    x_mean_rom[233] = 32'sh00006DA9;
    x_mean_rom[234] = 32'sh0004C3B0;
    x_mean_rom[235] = 32'sh00045FF6;
    x_mean_rom[236] = 32'sh00035142;
    x_mean_rom[237] = 32'sh0001E4E5;
    x_mean_rom[238] = 32'sh00007DA1;
    x_mean_rom[239] = 32'shFFFF7375;
    x_mean_rom[240] = 32'shFFFEF803;
    x_mean_rom[241] = 32'shFFFF0A45;
    x_mean_rom[242] = 32'shFFFF7CEC;
    x_mean_rom[243] = 32'sh00000B85;
    x_mean_rom[244] = 32'sh000075EB;
    x_mean_rom[245] = 32'sh000096D2;
    x_mean_rom[246] = 32'sh00006DA9;
    x_mean_rom[247] = 32'sh0004C3B0;
    x_mean_rom[248] = 32'sh00045FF6;
    x_mean_rom[249] = 32'sh00035142;
    x_mean_rom[250] = 32'sh0001E4E5;
    x_mean_rom[251] = 32'sh00007DA1;
    x_mean_rom[252] = 32'shFFFF7375;
    x_mean_rom[253] = 32'shFFFEF803;
    x_mean_rom[254] = 32'shFFFF0A45;
    x_mean_rom[255] = 32'shFFFF7CEC;
    x_mean_rom[256] = 32'sh00000B85;
    x_mean_rom[257] = 32'sh000075EB;
    x_mean_rom[258] = 32'sh000096D2;
    x_mean_rom[259] = 32'sh00006DA9;
    x_mean_rom[260] = 32'sh0004C3B0;
    x_mean_rom[261] = 32'sh00045FF6;
    x_mean_rom[262] = 32'sh00035142;
    x_mean_rom[263] = 32'sh0001E4E5;
    x_mean_rom[264] = 32'sh00007DA1;
    x_mean_rom[265] = 32'shFFFF7375;
    x_mean_rom[266] = 32'shFFFEF803;
    x_mean_rom[267] = 32'shFFFF0A45;
    x_mean_rom[268] = 32'shFFFF7CEC;
    x_mean_rom[269] = 32'sh00000B85;
    x_mean_rom[270] = 32'sh000075EB;
    x_mean_rom[271] = 32'sh000096D2;
    x_mean_rom[272] = 32'sh00006DA9;
    x_mean_rom[273] = 32'sh0004C3B0;
    x_mean_rom[274] = 32'sh00045FF6;
    x_mean_rom[275] = 32'sh00035142;
    x_mean_rom[276] = 32'sh0001E4E5;
    x_mean_rom[277] = 32'sh00007DA1;
    x_mean_rom[278] = 32'shFFFF7375;
    x_mean_rom[279] = 32'shFFFEF803;
    x_mean_rom[280] = 32'shFFFF0A45;
    x_mean_rom[281] = 32'shFFFF7CEC;
    x_mean_rom[282] = 32'sh00000B85;
    x_mean_rom[283] = 32'sh000075EB;
    x_mean_rom[284] = 32'sh000096D2;
    x_mean_rom[285] = 32'sh00006DA9;
    x_mean_rom[286] = 32'sh0004C3B0;
    x_mean_rom[287] = 32'sh00045FF6;
    x_mean_rom[288] = 32'sh00035142;
    x_mean_rom[289] = 32'sh0001E4E5;
    x_mean_rom[290] = 32'sh00007DA1;
    x_mean_rom[291] = 32'shFFFF7375;
    x_mean_rom[292] = 32'shFFFEF803;
    x_mean_rom[293] = 32'shFFFF0A45;
    x_mean_rom[294] = 32'shFFFF7CEC;
    x_mean_rom[295] = 32'sh00000B85;
    x_mean_rom[296] = 32'sh000075EB;
    x_mean_rom[297] = 32'sh000096D2;
    x_mean_rom[298] = 32'sh00006DA9;
    x_mean_rom[299] = 32'sh0004C3B0;
    x_mean_rom[300] = 32'sh00045FF6;
    x_mean_rom[301] = 32'sh00035142;
    x_mean_rom[302] = 32'sh0001E4E5;
    x_mean_rom[303] = 32'sh00007DA1;
    x_mean_rom[304] = 32'shFFFF7375;
    x_mean_rom[305] = 32'shFFFEF803;
    x_mean_rom[306] = 32'shFFFF0A45;
    x_mean_rom[307] = 32'shFFFF7CEC;
    x_mean_rom[308] = 32'sh00000B85;
    x_mean_rom[309] = 32'sh000075EB;
    x_mean_rom[310] = 32'sh000096D2;
    x_mean_rom[311] = 32'sh00006DA9;
    x_mean_rom[312] = 32'sh0004C3B0;
    x_mean_rom[313] = 32'sh00045FF6;
    x_mean_rom[314] = 32'sh00035142;
    x_mean_rom[315] = 32'sh0001E4E5;
    x_mean_rom[316] = 32'sh00007DA1;
    x_mean_rom[317] = 32'shFFFF7375;
    x_mean_rom[318] = 32'shFFFEF803;
    x_mean_rom[319] = 32'shFFFF0A45;
    x_mean_rom[320] = 32'shFFFF7CEC;
    x_mean_rom[321] = 32'sh00000B85;
    x_mean_rom[322] = 32'sh000075EB;
    x_mean_rom[323] = 32'sh000096D2;
    x_mean_rom[324] = 32'sh00006DA9;
    x_mean_rom[325] = 32'sh0004C3B0;
    x_mean_rom[326] = 32'sh00045FF6;
    x_mean_rom[327] = 32'sh00035142;
    x_mean_rom[328] = 32'sh0001E4E5;
    x_mean_rom[329] = 32'sh00007DA1;
    x_mean_rom[330] = 32'shFFFF7375;
    x_mean_rom[331] = 32'shFFFEF803;
    x_mean_rom[332] = 32'shFFFF0A45;
    x_mean_rom[333] = 32'shFFFF7CEC;
    x_mean_rom[334] = 32'sh00000B85;
    x_mean_rom[335] = 32'sh000075EB;
    x_mean_rom[336] = 32'sh000096D2;
    x_mean_rom[337] = 32'sh00006DA9;
    x_mean_rom[338] = 32'sh0004C3B0;
    x_mean_rom[339] = 32'sh00045FF6;
    x_mean_rom[340] = 32'sh00035142;
    x_mean_rom[341] = 32'sh0001E4E5;
    x_mean_rom[342] = 32'sh00007DA1;
    x_mean_rom[343] = 32'shFFFF7375;
    x_mean_rom[344] = 32'shFFFEF803;
    x_mean_rom[345] = 32'shFFFF0A45;
    x_mean_rom[346] = 32'shFFFF7CEC;
    x_mean_rom[347] = 32'sh00000B85;
    x_mean_rom[348] = 32'sh000075EB;
    x_mean_rom[349] = 32'sh000096D2;
    x_mean_rom[350] = 32'sh00006DA9;
    x_mean_rom[351] = 32'sh0004C3B0;
    x_mean_rom[352] = 32'sh00045FF6;
    x_mean_rom[353] = 32'sh00035142;
    x_mean_rom[354] = 32'sh0001E4E5;
    x_mean_rom[355] = 32'sh00007DA1;
    x_mean_rom[356] = 32'shFFFF7375;
    x_mean_rom[357] = 32'shFFFEF803;
    x_mean_rom[358] = 32'shFFFF0A45;
    x_mean_rom[359] = 32'shFFFF7CEC;
    x_mean_rom[360] = 32'sh00000B85;
    x_mean_rom[361] = 32'sh000075EB;
    x_mean_rom[362] = 32'sh000096D2;
    x_mean_rom[363] = 32'sh00006DA9;
    x_mean_rom[364] = 32'sh0004C3B0;
    x_mean_rom[365] = 32'sh00045FF6;
    x_mean_rom[366] = 32'sh00035142;
    x_mean_rom[367] = 32'sh0001E4E5;
    x_mean_rom[368] = 32'sh00007DA1;
    x_mean_rom[369] = 32'shFFFF7375;
    x_mean_rom[370] = 32'shFFFEF803;
    x_mean_rom[371] = 32'shFFFF0A45;
    x_mean_rom[372] = 32'shFFFF7CEC;
    x_mean_rom[373] = 32'sh00000B85;
    x_mean_rom[374] = 32'sh000075EB;
    x_mean_rom[375] = 32'sh000096D2;
    x_mean_rom[376] = 32'sh00006DA9;
    x_mean_rom[377] = 32'sh0004C3B0;
    x_mean_rom[378] = 32'sh00045FF6;
    x_mean_rom[379] = 32'sh00035142;
    x_mean_rom[380] = 32'sh0001E4E5;
    x_mean_rom[381] = 32'sh00007DA1;
    x_mean_rom[382] = 32'shFFFF7375;
    x_mean_rom[383] = 32'shFFFEF803;
    x_mean_rom[384] = 32'shFFFF0A45;
    x_mean_rom[385] = 32'shFFFF7CEC;
    x_mean_rom[386] = 32'sh00000B85;
    x_mean_rom[387] = 32'sh000075EB;
    x_mean_rom[388] = 32'sh000096D2;
    x_mean_rom[389] = 32'sh00006DA9;
    x_mean_rom[390] = 32'sh0004C3B0;
    x_mean_rom[391] = 32'sh00045FF6;
    x_mean_rom[392] = 32'sh00035142;
    x_mean_rom[393] = 32'sh0001E4E5;
    x_mean_rom[394] = 32'sh00007DA1;
    x_mean_rom[395] = 32'shFFFF7375;
    x_mean_rom[396] = 32'shFFFEF803;
    x_mean_rom[397] = 32'shFFFF0A45;
    x_mean_rom[398] = 32'shFFFF7CEC;
    x_mean_rom[399] = 32'sh00000B85;
    x_mean_rom[400] = 32'sh000075EB;
    x_mean_rom[401] = 32'sh000096D2;
    x_mean_rom[402] = 32'sh00006DA9;
    x_mean_rom[403] = 32'sh0004C3B0;
    x_mean_rom[404] = 32'sh00045FF6;
    x_mean_rom[405] = 32'sh00035142;
    x_mean_rom[406] = 32'sh0001E4E5;
    x_mean_rom[407] = 32'sh00007DA1;
    x_mean_rom[408] = 32'shFFFF7375;
    x_mean_rom[409] = 32'shFFFEF803;
    x_mean_rom[410] = 32'shFFFF0A45;
    x_mean_rom[411] = 32'shFFFF7CEC;
    x_mean_rom[412] = 32'sh00000B85;
    x_mean_rom[413] = 32'sh000075EB;
    x_mean_rom[414] = 32'sh000096D2;
    x_mean_rom[415] = 32'sh00006DA9;
end

(* rom_style = "distributed" *) reg [9:0] recip_rom [0:415];
initial begin
    recip_rom[  0] =  37;
    recip_rom[  1] =  40;
    recip_rom[  2] =  53;
    recip_rom[  3] =  96;
    recip_rom[  4] = 415;
    recip_rom[  5] = 280;
    recip_rom[  6] = 168;
    recip_rom[  7] = 194;
    recip_rom[  8] = 419;
    recip_rom[  9] = 612;
    recip_rom[ 10] = 281;
    recip_rom[ 11] = 261;
    recip_rom[ 12] = 420;
    recip_rom[ 13] =  37;
    recip_rom[ 14] =  40;
    recip_rom[ 15] =  53;
    recip_rom[ 16] =  96;
    recip_rom[ 17] = 415;
    recip_rom[ 18] = 280;
    recip_rom[ 19] = 168;
    recip_rom[ 20] = 194;
    recip_rom[ 21] = 419;
    recip_rom[ 22] = 612;
    recip_rom[ 23] = 281;
    recip_rom[ 24] = 261;
    recip_rom[ 25] = 420;
    recip_rom[ 26] =  37;
    recip_rom[ 27] =  40;
    recip_rom[ 28] =  53;
    recip_rom[ 29] =  96;
    recip_rom[ 30] = 415;
    recip_rom[ 31] = 280;
    recip_rom[ 32] = 168;
    recip_rom[ 33] = 194;
    recip_rom[ 34] = 419;
    recip_rom[ 35] = 612;
    recip_rom[ 36] = 281;
    recip_rom[ 37] = 261;
    recip_rom[ 38] = 420;
    recip_rom[ 39] =  37;
    recip_rom[ 40] =  40;
    recip_rom[ 41] =  53;
    recip_rom[ 42] =  96;
    recip_rom[ 43] = 415;
    recip_rom[ 44] = 280;
    recip_rom[ 45] = 168;
    recip_rom[ 46] = 194;
    recip_rom[ 47] = 419;
    recip_rom[ 48] = 612;
    recip_rom[ 49] = 281;
    recip_rom[ 50] = 261;
    recip_rom[ 51] = 420;
    recip_rom[ 52] =  37;
    recip_rom[ 53] =  40;
    recip_rom[ 54] =  53;
    recip_rom[ 55] =  96;
    recip_rom[ 56] = 415;
    recip_rom[ 57] = 280;
    recip_rom[ 58] = 168;
    recip_rom[ 59] = 194;
    recip_rom[ 60] = 419;
    recip_rom[ 61] = 612;
    recip_rom[ 62] = 281;
    recip_rom[ 63] = 261;
    recip_rom[ 64] = 420;
    recip_rom[ 65] =  37;
    recip_rom[ 66] =  40;
    recip_rom[ 67] =  53;
    recip_rom[ 68] =  96;
    recip_rom[ 69] = 415;
    recip_rom[ 70] = 280;
    recip_rom[ 71] = 168;
    recip_rom[ 72] = 194;
    recip_rom[ 73] = 419;
    recip_rom[ 74] = 612;
    recip_rom[ 75] = 281;
    recip_rom[ 76] = 261;
    recip_rom[ 77] = 420;
    recip_rom[ 78] =  37;
    recip_rom[ 79] =  40;
    recip_rom[ 80] =  53;
    recip_rom[ 81] =  96;
    recip_rom[ 82] = 415;
    recip_rom[ 83] = 280;
    recip_rom[ 84] = 168;
    recip_rom[ 85] = 194;
    recip_rom[ 86] = 419;
    recip_rom[ 87] = 612;
    recip_rom[ 88] = 281;
    recip_rom[ 89] = 261;
    recip_rom[ 90] = 420;
    recip_rom[ 91] =  37;
    recip_rom[ 92] =  40;
    recip_rom[ 93] =  53;
    recip_rom[ 94] =  96;
    recip_rom[ 95] = 415;
    recip_rom[ 96] = 280;
    recip_rom[ 97] = 168;
    recip_rom[ 98] = 194;
    recip_rom[ 99] = 419;
    recip_rom[100] = 612;
    recip_rom[101] = 281;
    recip_rom[102] = 261;
    recip_rom[103] = 420;
    recip_rom[104] =  37;
    recip_rom[105] =  40;
    recip_rom[106] =  53;
    recip_rom[107] =  96;
    recip_rom[108] = 415;
    recip_rom[109] = 280;
    recip_rom[110] = 168;
    recip_rom[111] = 194;
    recip_rom[112] = 419;
    recip_rom[113] = 612;
    recip_rom[114] = 281;
    recip_rom[115] = 261;
    recip_rom[116] = 420;
    recip_rom[117] =  37;
    recip_rom[118] =  40;
    recip_rom[119] =  53;
    recip_rom[120] =  96;
    recip_rom[121] = 415;
    recip_rom[122] = 280;
    recip_rom[123] = 168;
    recip_rom[124] = 194;
    recip_rom[125] = 419;
    recip_rom[126] = 612;
    recip_rom[127] = 281;
    recip_rom[128] = 261;
    recip_rom[129] = 420;
    recip_rom[130] =  37;
    recip_rom[131] =  40;
    recip_rom[132] =  53;
    recip_rom[133] =  96;
    recip_rom[134] = 415;
    recip_rom[135] = 280;
    recip_rom[136] = 168;
    recip_rom[137] = 194;
    recip_rom[138] = 419;
    recip_rom[139] = 612;
    recip_rom[140] = 281;
    recip_rom[141] = 261;
    recip_rom[142] = 420;
    recip_rom[143] =  37;
    recip_rom[144] =  40;
    recip_rom[145] =  53;
    recip_rom[146] =  96;
    recip_rom[147] = 415;
    recip_rom[148] = 280;
    recip_rom[149] = 168;
    recip_rom[150] = 194;
    recip_rom[151] = 419;
    recip_rom[152] = 612;
    recip_rom[153] = 281;
    recip_rom[154] = 261;
    recip_rom[155] = 420;
    recip_rom[156] =  37;
    recip_rom[157] =  40;
    recip_rom[158] =  53;
    recip_rom[159] =  96;
    recip_rom[160] = 415;
    recip_rom[161] = 280;
    recip_rom[162] = 168;
    recip_rom[163] = 194;
    recip_rom[164] = 419;
    recip_rom[165] = 612;
    recip_rom[166] = 281;
    recip_rom[167] = 261;
    recip_rom[168] = 420;
    recip_rom[169] =  37;
    recip_rom[170] =  40;
    recip_rom[171] =  53;
    recip_rom[172] =  96;
    recip_rom[173] = 415;
    recip_rom[174] = 280;
    recip_rom[175] = 168;
    recip_rom[176] = 194;
    recip_rom[177] = 419;
    recip_rom[178] = 612;
    recip_rom[179] = 281;
    recip_rom[180] = 261;
    recip_rom[181] = 420;
    recip_rom[182] =  37;
    recip_rom[183] =  40;
    recip_rom[184] =  53;
    recip_rom[185] =  96;
    recip_rom[186] = 415;
    recip_rom[187] = 280;
    recip_rom[188] = 168;
    recip_rom[189] = 194;
    recip_rom[190] = 419;
    recip_rom[191] = 612;
    recip_rom[192] = 281;
    recip_rom[193] = 261;
    recip_rom[194] = 420;
    recip_rom[195] =  37;
    recip_rom[196] =  40;
    recip_rom[197] =  53;
    recip_rom[198] =  96;
    recip_rom[199] = 415;
    recip_rom[200] = 280;
    recip_rom[201] = 168;
    recip_rom[202] = 194;
    recip_rom[203] = 419;
    recip_rom[204] = 612;
    recip_rom[205] = 281;
    recip_rom[206] = 261;
    recip_rom[207] = 420;
    recip_rom[208] =  37;
    recip_rom[209] =  40;
    recip_rom[210] =  53;
    recip_rom[211] =  96;
    recip_rom[212] = 415;
    recip_rom[213] = 280;
    recip_rom[214] = 168;
    recip_rom[215] = 194;
    recip_rom[216] = 419;
    recip_rom[217] = 612;
    recip_rom[218] = 281;
    recip_rom[219] = 261;
    recip_rom[220] = 420;
    recip_rom[221] =  37;
    recip_rom[222] =  40;
    recip_rom[223] =  53;
    recip_rom[224] =  96;
    recip_rom[225] = 415;
    recip_rom[226] = 280;
    recip_rom[227] = 168;
    recip_rom[228] = 194;
    recip_rom[229] = 419;
    recip_rom[230] = 612;
    recip_rom[231] = 281;
    recip_rom[232] = 261;
    recip_rom[233] = 420;
    recip_rom[234] =  37;
    recip_rom[235] =  40;
    recip_rom[236] =  53;
    recip_rom[237] =  96;
    recip_rom[238] = 415;
    recip_rom[239] = 280;
    recip_rom[240] = 168;
    recip_rom[241] = 194;
    recip_rom[242] = 419;
    recip_rom[243] = 612;
    recip_rom[244] = 281;
    recip_rom[245] = 261;
    recip_rom[246] = 420;
    recip_rom[247] =  37;
    recip_rom[248] =  40;
    recip_rom[249] =  53;
    recip_rom[250] =  96;
    recip_rom[251] = 415;
    recip_rom[252] = 280;
    recip_rom[253] = 168;
    recip_rom[254] = 194;
    recip_rom[255] = 419;
    recip_rom[256] = 612;
    recip_rom[257] = 281;
    recip_rom[258] = 261;
    recip_rom[259] = 420;
    recip_rom[260] =  37;
    recip_rom[261] =  40;
    recip_rom[262] =  53;
    recip_rom[263] =  96;
    recip_rom[264] = 415;
    recip_rom[265] = 280;
    recip_rom[266] = 168;
    recip_rom[267] = 194;
    recip_rom[268] = 419;
    recip_rom[269] = 612;
    recip_rom[270] = 281;
    recip_rom[271] = 261;
    recip_rom[272] = 420;
    recip_rom[273] =  37;
    recip_rom[274] =  40;
    recip_rom[275] =  53;
    recip_rom[276] =  96;
    recip_rom[277] = 415;
    recip_rom[278] = 280;
    recip_rom[279] = 168;
    recip_rom[280] = 194;
    recip_rom[281] = 419;
    recip_rom[282] = 612;
    recip_rom[283] = 281;
    recip_rom[284] = 261;
    recip_rom[285] = 420;
    recip_rom[286] =  37;
    recip_rom[287] =  40;
    recip_rom[288] =  53;
    recip_rom[289] =  96;
    recip_rom[290] = 415;
    recip_rom[291] = 280;
    recip_rom[292] = 168;
    recip_rom[293] = 194;
    recip_rom[294] = 419;
    recip_rom[295] = 612;
    recip_rom[296] = 281;
    recip_rom[297] = 261;
    recip_rom[298] = 420;
    recip_rom[299] =  37;
    recip_rom[300] =  40;
    recip_rom[301] =  53;
    recip_rom[302] =  96;
    recip_rom[303] = 415;
    recip_rom[304] = 280;
    recip_rom[305] = 168;
    recip_rom[306] = 194;
    recip_rom[307] = 419;
    recip_rom[308] = 612;
    recip_rom[309] = 281;
    recip_rom[310] = 261;
    recip_rom[311] = 420;
    recip_rom[312] =  37;
    recip_rom[313] =  40;
    recip_rom[314] =  53;
    recip_rom[315] =  96;
    recip_rom[316] = 415;
    recip_rom[317] = 280;
    recip_rom[318] = 168;
    recip_rom[319] = 194;
    recip_rom[320] = 419;
    recip_rom[321] = 612;
    recip_rom[322] = 281;
    recip_rom[323] = 261;
    recip_rom[324] = 420;
    recip_rom[325] =  37;
    recip_rom[326] =  40;
    recip_rom[327] =  53;
    recip_rom[328] =  96;
    recip_rom[329] = 415;
    recip_rom[330] = 280;
    recip_rom[331] = 168;
    recip_rom[332] = 194;
    recip_rom[333] = 419;
    recip_rom[334] = 612;
    recip_rom[335] = 281;
    recip_rom[336] = 261;
    recip_rom[337] = 420;
    recip_rom[338] =  37;
    recip_rom[339] =  40;
    recip_rom[340] =  53;
    recip_rom[341] =  96;
    recip_rom[342] = 415;
    recip_rom[343] = 280;
    recip_rom[344] = 168;
    recip_rom[345] = 194;
    recip_rom[346] = 419;
    recip_rom[347] = 612;
    recip_rom[348] = 281;
    recip_rom[349] = 261;
    recip_rom[350] = 420;
    recip_rom[351] =  37;
    recip_rom[352] =  40;
    recip_rom[353] =  53;
    recip_rom[354] =  96;
    recip_rom[355] = 415;
    recip_rom[356] = 280;
    recip_rom[357] = 168;
    recip_rom[358] = 194;
    recip_rom[359] = 419;
    recip_rom[360] = 612;
    recip_rom[361] = 281;
    recip_rom[362] = 261;
    recip_rom[363] = 420;
    recip_rom[364] =  37;
    recip_rom[365] =  40;
    recip_rom[366] =  53;
    recip_rom[367] =  96;
    recip_rom[368] = 415;
    recip_rom[369] = 280;
    recip_rom[370] = 168;
    recip_rom[371] = 194;
    recip_rom[372] = 419;
    recip_rom[373] = 612;
    recip_rom[374] = 281;
    recip_rom[375] = 261;
    recip_rom[376] = 420;
    recip_rom[377] =  37;
    recip_rom[378] =  40;
    recip_rom[379] =  53;
    recip_rom[380] =  96;
    recip_rom[381] = 415;
    recip_rom[382] = 280;
    recip_rom[383] = 168;
    recip_rom[384] = 194;
    recip_rom[385] = 419;
    recip_rom[386] = 612;
    recip_rom[387] = 281;
    recip_rom[388] = 261;
    recip_rom[389] = 420;
    recip_rom[390] =  37;
    recip_rom[391] =  40;
    recip_rom[392] =  53;
    recip_rom[393] =  96;
    recip_rom[394] = 415;
    recip_rom[395] = 280;
    recip_rom[396] = 168;
    recip_rom[397] = 194;
    recip_rom[398] = 419;
    recip_rom[399] = 612;
    recip_rom[400] = 281;
    recip_rom[401] = 261;
    recip_rom[402] = 420;
    recip_rom[403] =  37;
    recip_rom[404] =  40;
    recip_rom[405] =  53;
    recip_rom[406] =  96;
    recip_rom[407] = 415;
    recip_rom[408] = 280;
    recip_rom[409] = 168;
    recip_rom[410] = 194;
    recip_rom[411] = 419;
    recip_rom[412] = 612;
    recip_rom[413] = 281;
    recip_rom[414] = 261;
    recip_rom[415] = 420;
end

// L1 biases (W_SCALE=1024; acc >> MAC_SHIFT=10 matches float)
wire signed [31:0] l1_bias [0:15];
assign l1_bias[ 0] = 32'shFFFFFF34; assign l1_bias[ 1] = 32'shFFFFFCD2;
assign l1_bias[ 2] = 32'shFFFFFE61; assign l1_bias[ 3] = 32'sh00000183;
assign l1_bias[ 4] = 32'shFFFFFE64; assign l1_bias[ 5] = 32'shFFFFFBD6;
assign l1_bias[ 6] = 32'shFFFFFE4A; assign l1_bias[ 7] = 32'shFFFFFD3B;
assign l1_bias[ 8] = 32'shFFFFFE97; assign l1_bias[ 9] = 32'shFFFFFF1B;
assign l1_bias[10] = 32'shFFFFFEF1; assign l1_bias[11] = 32'shFFFFFFD7;
assign l1_bias[12] = 32'shFFFFFD7E; assign l1_bias[13] = 32'shFFFFFF66;
assign l1_bias[14] = 32'shFFFFFD77; assign l1_bias[15] = 32'shFFFFFD7E;

// L2 biases (b2[0]>>10=0, b2[1]>>10=-1, gap=1 verified by golden model)
wire signed [31:0] l2_bias [0:1];
assign l2_bias[0] = 32'sh00000073;
assign l2_bias[1] = 32'shFFFFFF3E;

wire signed [31:0] acc_shifted = acc >>> MAC_SHIFT;
wire signed [31:0] acc_relu    = acc_shifted[31] ? 32'd0 : acc_shifted;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= S_IDLE;
        valid       <= 1'b0;
        logit0      <= 32'd0;
        logit1      <= 32'd0;
        idx         <= 9'd0;
        neuron      <= 5'd0;
        acc         <= 32'd0;
        norm_diff_r <= 32'd0;
        norm_idx_r  <= 9'd0;
        w1_base     <= 13'd0;
    end else begin
        valid <= 1'b0;

        case (state)
        S_IDLE: begin
            if (start) begin
                norm_diff_r <= mfcc_in[0] - x_mean_rom[0];
                norm_idx_r  <= 9'd0;
                idx         <= 9'd1;
                state       <= S_NORM;
            end
        end

        // Pipelined norm: 417 cycles (1 latency + 416 results)
        S_NORM: begin
            x_norm[norm_idx_r] <= norm_clipped;

            if (idx <= 9'd415) begin
                norm_diff_r <= mfcc_in[idx] - x_mean_rom[idx];
                norm_idx_r  <= idx;
                idx         <= idx + 9'd1;
            end else begin
                neuron  <= 5'd0;
                idx     <= 9'd0;
                w1_base <= 13'd0;
                acc     <= l1_bias[0];
                state   <= S_L1_MAC;
            end
        end

        // L1: 16 neurons x (416 MAC + 1 WB) = 6,672 cycles
        S_L1_MAC: begin
            acc <= acc + (w1_val * x_norm[idx]);
            if (idx == 9'd415)
                state <= S_L1_WB;
            else
                idx <= idx + 9'd1;
        end

        S_L1_WB: begin
            l1_out[neuron[3:0]] <= acc_relu;

            if (neuron == 5'd15) begin
                neuron <= 5'd0;
                idx    <= 9'd0;
                acc    <= l2_bias[0];
                state  <= S_L2_MAC;
            end else begin
                neuron  <= neuron + 5'd1;
                idx     <= 9'd0;
                w1_base <= w1_base + 13'd416;
                acc     <= l1_bias[neuron + 1];
                state   <= S_L1_MAC;
            end
        end

        // L2: 2 neurons x (16 MAC + 1 WB) = 34 cycles
        S_L2_MAC: begin
            acc <= acc + (w2_val * l1_out[idx[3:0]]);
            if (idx == 9'd15)
                state <= S_L2_WB;
            else
                idx <= idx + 9'd1;
        end

        S_L2_WB: begin
            if (neuron == 5'd0) begin
                logit0 <= acc_shifted;
                neuron <= 5'd1;
                idx    <= 9'd0;
                acc    <= l2_bias[1];
                state  <= S_L2_MAC;
            end else begin
                logit1 <= acc_shifted;
                state  <= S_OUTPUT;
            end
        end

        S_OUTPUT: begin
            valid <= 1'b1;
            state <= S_IDLE;
        end

        default: state <= S_IDLE;
        endcase
    end
end

endmodule
