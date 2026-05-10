//`timescale 1ns / 1ps

//module mfcc_processor #(
//    parameter NUM_MEL  = 26,
//    parameter NUM_CEP  = 13,
//    parameter FFT_BINS = 256
//)(
//    input  wire        clk,
//    input  wire        rst_n,       // Active-low - connect to top's aresetn

//    // ?? AXI-Stream from Xilinx CORDIC IP (magnitude output) ?????????????????
//    input  wire [31:0] mag_tdata,   // [15:0] = magnitude, [31:16] = ignored
//    input  wire        mag_tvalid,
//    input  wire        mag_tlast,   // High on last bin of each FFT frame
//    output wire        mag_tready,  // Back-pressure

//    // ?? MFCC Coefficient Output ??????????????????????????????????????????????
//    output reg signed [31:0] mfcc_coeff_out,
//    output reg         mfcc_valid,
//    output reg         mfcc_last,
//    output wire signed [39:0] dct_accum_probe
//);

//// =============================================================================
//// Derived parameters
//// =============================================================================
//localparam DCT_ROM_DEPTH = NUM_CEP * NUM_MEL;   // 338

//// =============================================================================
//// FSM states
//// =============================================================================
//localparam [3:0]
//    ST_IDLE           = 4'd0,
//    ST_ACCUM_CAPTURE  = 4'd1,
//    ST_ACCUM_MUL      = 4'd2,
//    ST_ACCUM_WRITE    = 4'd3,
//    ST_LOG_CAPTURE    = 4'd4,
//    ST_LOG_COMPUTE    = 4'd5,
//    ST_LOG_WRITE      = 4'd6,
//    ST_DCT_CAPTURE    = 4'd7,
//    ST_DCT_MUL        = 4'd8,
//    ST_DCT_ACC        = 4'd9,
//    ST_OUT            = 4'd10;

//reg [3:0] state;

//// =============================================================================
//// Counters
//// =============================================================================
//reg [8:0] bin_cnt;          // *** FIX: 9 bits to count 0..511 without wrapping ***
//reg [4:0] mel_idx;
//reg [3:0] cep_idx;
//reg [31:0] log_input_reg;
//reg [15:0] log_result_reg;
//reg signed [16:0] dct_log_reg;
//reg signed [15:0] dct_coeff_reg;
//reg signed [32:0] dct_prod_reg;

//// =============================================================================
//// 1.  AXI-S back-pressure
//// =============================================================================
//assign mag_tready = (state == ST_ACCUM_CAPTURE);

//// =============================================================================
//// 2.  Magnitude extraction
//// =============================================================================
//wire [15:0] magnitude = mag_tdata[15:0];

//// =============================================================================
//// 3.  Mel Filter Bank ROM  (256 × 26-bit, distributed RAM)
//// =============================================================================
//(* ram_style = "distributed" *)
//reg [25:0] mel_rom [0:255];
//initial $readmemh("C:/Users/HP/Desktop/FDP-master/FDP-master/mel_filter_rom.hex", mel_rom);

//wire [4:0]  mel_bank_lo = mel_rom[bin_cnt[7:0]][25:21];
//wire [4:0]  mel_bank_hi = mel_rom[bin_cnt[7:0]][20:16];
//wire [15:0] mel_wt_lo   = mel_rom[bin_cnt[7:0]][15:0];
//wire [15:0] mel_wt_hi   = 16'hFFFF - mel_wt_lo;

//wire [31:0] prod_lo = ({16'b0, magnitude} * {16'b0, mel_wt_lo}) >> 16;
//wire [31:0] prod_hi = ({16'b0, magnitude} * {16'b0, mel_wt_hi}) >> 16;

//// =============================================================================
//// 4.  Mel Accumulators  (26 × 32-bit)
//// =============================================================================
//reg [31:0] mel_accum [0:NUM_MEL-1];
//integer ii;

//always @(posedge clk or negedge rst_n) begin
//    if (!rst_n) begin
//        for (ii = 0; ii < NUM_MEL; ii = ii + 1)
//            mel_accum[ii] <= 32'd0;
//    end else if (state == ST_IDLE) begin
//        for (ii = 0; ii < NUM_MEL; ii = ii + 1)
//            mel_accum[ii] <= 32'd0;
//    // *** FIX: Only accumulate bins 0..255 (first half of real FFT) ***
//    end else if (state == ST_ACCUM_CAPTURE && mag_tvalid && bin_cnt < FFT_BINS && bin_cnt > 0) begin
//        if (mel_bank_lo != 5'h1F)
//            mel_accum[mel_bank_lo] <= mel_accum[mel_bank_lo] + prod_lo;
//        if ((mel_bank_hi != 5'h1F) && (mel_bank_hi != mel_bank_lo))
//            mel_accum[mel_bank_hi] <= mel_accum[mel_bank_hi] + prod_hi;
//    end
//end

//// =============================================================================
//// 5.  Bin counter  (9-bit to handle full 512-bin FFT output)
//// =============================================================================
//always @(posedge clk or negedge rst_n) begin
//    if (!rst_n)
//        bin_cnt <= 9'd0;
//    else if (state == ST_IDLE)
//        bin_cnt <= 9'd0;
//    else if (state == ST_ACCUM_CAPTURE && mag_tvalid)
//        bin_cnt <= mag_tlast ? 9'd0 : bin_cnt + 9'd1;
//end

//// =============================================================================
//// 6.  log? Approximation
//// =============================================================================

//function [4:0] lzc32;
//    input [31:0] x;
//    integer k;
//    reg found;
//    begin
//        lzc32 = 5'd31;
//        found = 1'b0;

//        for (k = 31; k >= 0; k = k - 1) begin
//            if (!found && x[k]) begin
//                lzc32 = 5'd31 - k[4:0];
//                found = 1'b1;
//            end
//        end
//    end
//endfunction

//(* ram_style = "distributed" *)
//reg [7:0] log2_frac_lut [0:63];
//initial begin
//    log2_frac_lut[ 0]=8'd  0; log2_frac_lut[ 1]=8'd  6; log2_frac_lut[ 2]=8'd 11;
//    log2_frac_lut[ 3]=8'd 17; log2_frac_lut[ 4]=8'd 22; log2_frac_lut[ 5]=8'd 28;
//    log2_frac_lut[ 6]=8'd 33; log2_frac_lut[ 7]=8'd 38; log2_frac_lut[ 8]=8'd 43;
//    log2_frac_lut[ 9]=8'd 49; log2_frac_lut[10]=8'd 54; log2_frac_lut[11]=8'd 59;
//    log2_frac_lut[12]=8'd 64; log2_frac_lut[13]=8'd 69; log2_frac_lut[14]=8'd 73;
//    log2_frac_lut[15]=8'd 78; log2_frac_lut[16]=8'd 82; log2_frac_lut[17]=8'd 87;
//    log2_frac_lut[18]=8'd 92; log2_frac_lut[19]=8'd 96; log2_frac_lut[20]=8'd101;
//    log2_frac_lut[21]=8'd105; log2_frac_lut[22]=8'd109; log2_frac_lut[23]=8'd113;
//    log2_frac_lut[24]=8'd118; log2_frac_lut[25]=8'd121; log2_frac_lut[26]=8'd126;
//    log2_frac_lut[27]=8'd130; log2_frac_lut[28]=8'd134; log2_frac_lut[29]=8'd137;
//    log2_frac_lut[30]=8'd141; log2_frac_lut[31]=8'd145; log2_frac_lut[32]=8'd150;
//    log2_frac_lut[33]=8'd153; log2_frac_lut[34]=8'd157; log2_frac_lut[35]=8'd161;
//    log2_frac_lut[36]=8'd165; log2_frac_lut[37]=8'd168; log2_frac_lut[38]=8'd172;
//    log2_frac_lut[39]=8'd175; log2_frac_lut[40]=8'd179; log2_frac_lut[41]=8'd183;
//    log2_frac_lut[42]=8'd186; log2_frac_lut[43]=8'd190; log2_frac_lut[44]=8'd193;
//    log2_frac_lut[45]=8'd197; log2_frac_lut[46]=8'd200; log2_frac_lut[47]=8'd204;
//    log2_frac_lut[48]=8'd207; log2_frac_lut[49]=8'd210; log2_frac_lut[50]=8'd213;
//    log2_frac_lut[51]=8'd217; log2_frac_lut[52]=8'd220; log2_frac_lut[53]=8'd223;
//    log2_frac_lut[54]=8'd226; log2_frac_lut[55]=8'd229; log2_frac_lut[56]=8'd232;
//    log2_frac_lut[57]=8'd235; log2_frac_lut[58]=8'd238; log2_frac_lut[59]=8'd241;
//    log2_frac_lut[60]=8'd244; log2_frac_lut[61]=8'd247; log2_frac_lut[62]=8'd250;
//    log2_frac_lut[63]=8'd253;
//end

//wire [4:0]  log_lzc      = lzc32(log_input_reg);
//wire [4:0]  log_intpart  = (log_input_reg == 32'd0) ? 5'd0 : (5'd31 - log_lzc);
//wire [31:0] log_normed   = log_input_reg << log_lzc;
//wire [5:0]  log_frac_idx = log_normed[30:25];
//wire [7:0]  log_fracpart = log2_frac_lut[log_frac_idx];
//wire [15:0] log_result_next = (log_input_reg == 32'd0) ? 16'd0
//                          : {3'b000, log_intpart, log_fracpart};

//reg [15:0] log_mel [0:NUM_MEL-1];

//// =============================================================================
//// 7.  DCT-II Cosine ROM  (338 × 16-bit Q1.15 signed)
//// =============================================================================
//(* ram_style = "distributed" *)
//reg signed [15:0] dct_cos_rom [0:DCT_ROM_DEPTH-1];
//initial $readmemh("C:/Users/HP/Desktop/FDP-master/FDP-master/dct_cos_rom.hex", dct_cos_rom);

//wire [8:0] dct_rom_addr_next = (cep_idx * NUM_MEL) + mel_idx;
//wire signed [32:0] dct_prod_next = dct_log_reg * dct_coeff_reg;

//reg signed [39:0] dct_accum;

//function signed [31:0] round_shift8;
//    input signed [39:0] x;
//    begin
//        if (x >= 0)
//            round_shift8 = (x + 40'sd128) >>> 8;
//        else
//            round_shift8 = -(((-x) + 40'sd128) >>> 8);
//    end
//endfunction

//// =============================================================================
//// 8.  Main FSM
//// =============================================================================
//integer jj;

//always @(posedge clk or negedge rst_n) begin
//    if (!rst_n) begin
//        state          <= ST_IDLE;
//        mel_idx        <= 5'd0;
//        cep_idx        <= 4'd0;
//        log_input_reg  <= 32'd0;
//        log_result_reg <= 16'd0;
//        dct_log_reg    <= 17'sd0;
//        dct_coeff_reg  <= 16'sd0;
//        dct_prod_reg   <= 33'sd0;
//        dct_accum      <= 40'sd0;
//        mfcc_coeff_out <= 32'sd0;
//        mfcc_valid     <= 1'b0;
//        mfcc_last      <= 1'b0;
//        for (jj = 0; jj < NUM_MEL; jj = jj + 1)
//            log_mel[jj] <= 16'd0;
//    end else begin

//        mfcc_valid <= 1'b0;
//        mfcc_last  <= 1'b0;

//        case (state)

//            ST_IDLE: begin
//                mel_idx   <= 5'd0;
//                cep_idx   <= 4'd0;
//                dct_accum <= 40'sd0;
//                state     <= ST_ACCUM_CAPTURE;
//            end

//            ST_ACCUM_CAPTURE: begin
//                if (mag_tvalid && mag_tlast) begin
//                    mel_idx <= 5'd0;
//                    state   <= ST_LOG_CAPTURE;
//                end
//            end

//            ST_LOG_CAPTURE: begin
//                log_input_reg <= mel_accum[mel_idx];
//                state         <= ST_LOG_COMPUTE;
//            end

//            ST_LOG_COMPUTE: begin
//                log_result_reg <= log_result_next;
//                state          <= ST_LOG_WRITE;
//            end

//            ST_LOG_WRITE: begin
//                log_mel[mel_idx] <= log_result_reg;
//                if (mel_idx == NUM_MEL - 1) begin
//                    mel_idx   <= 5'd0;
//                    cep_idx   <= 4'd0;
//                    dct_accum <= 40'sd0;
//                    state     <= ST_DCT_CAPTURE;
//                end else begin
//                    mel_idx <= mel_idx + 5'd1;
//                    state   <= ST_LOG_CAPTURE;
//                end
//            end

//            ST_DCT_CAPTURE: begin
//                dct_log_reg   <= {1'b0, log_mel[mel_idx][15:3]};
//                dct_coeff_reg <= dct_cos_rom[dct_rom_addr_next];
//                state         <= ST_DCT_MUL;
//            end

//            ST_DCT_MUL: begin
//                dct_prod_reg <= dct_prod_next;
//                state        <= ST_DCT_ACC;
//            end

//            ST_DCT_ACC: begin
//                dct_accum <= (mel_idx == 5'd0)
//                    ? {{7{dct_prod_reg[32]}}, dct_prod_reg}
//                    : dct_accum + {{7{dct_prod_reg[32]}}, dct_prod_reg};

//                if (mel_idx == NUM_MEL - 1) begin
//                    mel_idx <= 5'd0;
//                    state   <= ST_OUT;
//                end else begin
//                    mel_idx <= mel_idx + 5'd1;
//                    state   <= ST_DCT_CAPTURE;
//                end
//            end

//            ST_OUT: begin
//                mfcc_coeff_out <= round_shift8(dct_accum);
//                mfcc_valid     <= 1'b1;

//                if (cep_idx == NUM_CEP - 1) begin
//                    mfcc_last <= 1'b1;
//                    state     <= ST_IDLE;
//                end else begin
//                    cep_idx   <= cep_idx + 4'd1;
//                    mel_idx   <= 5'd0;
//                    dct_accum <= 40'sd0;
//                    state     <= ST_DCT_CAPTURE;
//                end
//            end

//            default: state <= ST_IDLE;
//        endcase
//    end
//end

//assign dct_accum_probe = dct_accum;

//endmodule

`timescale 1ns / 1ps

module mfcc_processor #(
    parameter NUM_MEL  = 26,
    parameter NUM_CEP  = 13,
    parameter FFT_BINS = 256
)(
    input  wire        clk,
    input  wire        rst_n,       // Active-low - connect to top's aresetn

    // ?? AXI-Stream from Xilinx CORDIC IP (magnitude output) ?????????????????
    // Connect to:  cordic_ip's  m_axis_dout_tdata / _tvalid / _tlast
    // cordic_out_data[15:0] = |H[k]|  (Cartesian-to-polar CORDIC output)
    input  wire [31:0] mag_tdata,   // [15:0] = magnitude, [31:16] = ignored
    input  wire        mag_tvalid,
    input  wire        mag_tlast,   // High on last bin of each FFT frame
    output wire        mag_tready,  // Back-pressure - replaces the 1'b1 tie-off

    // ?? MFCC Coefficient Output ??????????????????????????????????????????????
    output reg signed [31:0] mfcc_coeff_out,   // Signed. Divide by 2^15 for float.
    output reg         mfcc_valid,       // 1-cycle pulse per coefficient
    output reg         mfcc_last,         // High with the 13th coefficient
    output wire signed [39:0] dct_accum_probe
);

// =============================================================================
// Derived parameters
// =============================================================================
localparam DCT_ROM_DEPTH = NUM_CEP * NUM_MEL;   // 338

// =============================================================================
// FSM states
// =============================================================================
localparam [3:0]
    ST_IDLE           = 4'd0,
    ST_ACCUM_CAPTURE  = 4'd1,
    ST_ACCUM_MUL      = 4'd2,
    ST_ACCUM_WRITE    = 4'd3,
    ST_LOG_CAPTURE    = 4'd4,
    ST_LOG_COMPUTE    = 4'd5,
    ST_LOG_WRITE      = 4'd6,
    ST_DCT_CAPTURE    = 4'd7,
    ST_DCT_MUL        = 4'd8,
    ST_DCT_ACC        = 4'd9,
    ST_OUT            = 4'd10;

reg [3:0] state;

// =============================================================================
// Counters
// =============================================================================
reg [7:0] bin_cnt;
reg [4:0] mel_idx;
reg [3:0] cep_idx;
reg [31:0] log_input_reg;
reg [15:0] log_result_reg;
reg signed [16:0] dct_log_reg;
reg signed [15:0] dct_coeff_reg;
reg signed [32:0] dct_prod_reg;

// =============================================================================
// 1.  AXI-S back-pressure
//     Signal ready only while accumulating - CORDIC will hold its data.
// =============================================================================
assign mag_tready = (state == ST_ACCUM_CAPTURE);

// =============================================================================
// 2.  Magnitude extraction
//     Xilinx CORDIC Cartesian-to-Polar: magnitude on lower 16 bits of dout.
// =============================================================================
wire [15:0] magnitude = mag_tdata[15:0];

// =============================================================================
// 3.  Mel Filter Bank ROM  (256   26-bit, distributed RAM)
//
//     [25:21] bank_lo  - lower filter index  (5'h1F = bin outside all filters)
//     [20:16] bank_hi  - upper filter index
//     [15: 0] wt_lo    - Q0.16 weight for bank_lo; wt_hi = 0xFFFF - wt_lo
//
//     Generate: python3 mfcc_rom_gen.py
// =============================================================================
(* ram_style = "distributed" *)
reg [25:0] mel_rom [0:255];
initial $readmemh("C:/Users/HP/Desktop/mel_filter_rom.hex", mel_rom);

wire [4:0]  mel_bank_lo = mel_rom[bin_cnt][25:21];
wire [4:0]  mel_bank_hi = mel_rom[bin_cnt][20:16];
wire [15:0] mel_wt_lo   = mel_rom[bin_cnt][15:0];
wire [15:0] mel_wt_hi   = 16'hFFFF - mel_wt_lo;

wire [31:0] prod_lo = ({16'b0, magnitude} * {16'b0, mel_wt_lo}) >> 16;
wire [31:0] prod_hi = ({16'b0, magnitude} * {16'b0, mel_wt_hi}) >> 16;

// =============================================================================
// 4.  Mel Accumulators  (26   32-bit, cleared in ST_IDLE)
// =============================================================================
reg [31:0] mel_accum [0:NUM_MEL-1];
integer ii;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (ii = 0; ii < NUM_MEL; ii = ii + 1)
            mel_accum[ii] <= 32'd0;
    end else if (state == ST_IDLE) begin
        for (ii = 0; ii < NUM_MEL; ii = ii + 1)
            mel_accum[ii] <= 32'd0;
    end else if (state == ST_ACCUM_CAPTURE && mag_tvalid && bin_cnt < FFT_BINS) begin
        if (mel_bank_lo != 5'h1F)
            mel_accum[mel_bank_lo] <= mel_accum[mel_bank_lo] + prod_lo;
        if ((mel_bank_hi != 5'h1F) && (mel_bank_hi != mel_bank_lo))
            mel_accum[mel_bank_hi] <= mel_accum[mel_bank_hi] + prod_hi;
    end
end

// =============================================================================
// 5.  Bin counter
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        bin_cnt <= 8'd0;
    else if (state == ST_IDLE)
        bin_cnt <= 8'd0;
    else if (state == ST_ACCUM_CAPTURE && mag_tvalid)
        bin_cnt <= mag_tlast ? 8'd0 : bin_cnt + 8'd1;
end

// =============================================================================
// 6.  log? Approximation
//     log?(x) = (31 - LZC(x)) + frac_LUT[mantissa[30:25]]
//     Output: Q8.8 unsigned  (max = 31.996)
// =============================================================================

function [4:0] lzc32;
    input [31:0] x;
    integer k;
    reg found;
    begin
        lzc32 = 5'd31;
        found = 1'b0;

        for (k = 31; k >= 0; k = k - 1) begin
            if (!found && x[k]) begin
                lzc32 = 5'd31 - k[4:0];
                found = 1'b1;
            end
        end
    end
endfunction

(* ram_style = "distributed" *)
reg [7:0] log2_frac_lut [0:63];
initial begin
    log2_frac_lut[ 0]=8'd  0; log2_frac_lut[ 1]=8'd  6; log2_frac_lut[ 2]=8'd 11;
    log2_frac_lut[ 3]=8'd 17; log2_frac_lut[ 4]=8'd 22; log2_frac_lut[ 5]=8'd 28;
    log2_frac_lut[ 6]=8'd 33; log2_frac_lut[ 7]=8'd 38; log2_frac_lut[ 8]=8'd 43;
    log2_frac_lut[ 9]=8'd 49; log2_frac_lut[10]=8'd 54; log2_frac_lut[11]=8'd 59;
    log2_frac_lut[12]=8'd 64; log2_frac_lut[13]=8'd 69; log2_frac_lut[14]=8'd 73;
    log2_frac_lut[15]=8'd 78; log2_frac_lut[16]=8'd 82; log2_frac_lut[17]=8'd 87;
    log2_frac_lut[18]=8'd 92; log2_frac_lut[19]=8'd 96; log2_frac_lut[20]=8'd101;
    log2_frac_lut[21]=8'd105; log2_frac_lut[22]=8'd109; log2_frac_lut[23]=8'd113;
    log2_frac_lut[24]=8'd118; log2_frac_lut[25]=8'd121; log2_frac_lut[26]=8'd126;
    log2_frac_lut[27]=8'd130; log2_frac_lut[28]=8'd134; log2_frac_lut[29]=8'd137;
    log2_frac_lut[30]=8'd141; log2_frac_lut[31]=8'd145; log2_frac_lut[32]=8'd150;
    log2_frac_lut[33]=8'd153; log2_frac_lut[34]=8'd157; log2_frac_lut[35]=8'd161;
    log2_frac_lut[36]=8'd165; log2_frac_lut[37]=8'd168; log2_frac_lut[38]=8'd172;
    log2_frac_lut[39]=8'd175; log2_frac_lut[40]=8'd179; log2_frac_lut[41]=8'd183;
    log2_frac_lut[42]=8'd186; log2_frac_lut[43]=8'd190; log2_frac_lut[44]=8'd193;
    log2_frac_lut[45]=8'd197; log2_frac_lut[46]=8'd200; log2_frac_lut[47]=8'd204;
    log2_frac_lut[48]=8'd207; log2_frac_lut[49]=8'd210; log2_frac_lut[50]=8'd213;
    log2_frac_lut[51]=8'd217; log2_frac_lut[52]=8'd220; log2_frac_lut[53]=8'd223;
    log2_frac_lut[54]=8'd226; log2_frac_lut[55]=8'd229; log2_frac_lut[56]=8'd232;
    log2_frac_lut[57]=8'd235; log2_frac_lut[58]=8'd238; log2_frac_lut[59]=8'd241;
    log2_frac_lut[60]=8'd244; log2_frac_lut[61]=8'd247; log2_frac_lut[62]=8'd250;
    log2_frac_lut[63]=8'd253;
end

wire [4:0]  log_lzc      = lzc32(log_input_reg);
wire [4:0]  log_intpart  = (log_input_reg == 32'd0) ? 5'd0 : (5'd31 - log_lzc);
wire [31:0] log_normed   = log_input_reg << log_lzc;
wire [5:0]  log_frac_idx = log_normed[30:25];
wire [7:0]  log_fracpart = log2_frac_lut[log_frac_idx];
wire [15:0] log_result_next = (log_input_reg == 32'd0) ? 16'd0
                          : {3'b000, log_intpart, log_fracpart};

reg [15:0] log_mel [0:NUM_MEL-1];

// =============================================================================
// 7.  DCT-II Cosine ROM  (338   16-bit Q1.15 signed)
//     ROM[m*NUM_MEL + l] = round( cos(? m (l+0.5)/NUM_MEL)   32767 )
// =============================================================================
(* ram_style = "distributed" *)
reg signed [15:0] dct_cos_rom [0:DCT_ROM_DEPTH-1];
initial $readmemh("C:/Users/HP/Desktop/dct_cos_rom.hex", dct_cos_rom);

wire [8:0] dct_rom_addr_next = (cep_idx * NUM_MEL) + mel_idx;
wire signed [32:0] dct_prod_next = dct_log_reg * dct_coeff_reg;

reg signed [39:0] dct_accum;

function signed [31:0] round_shift8;
    input signed [39:0] x;
    begin
        if (x >= 0)
            round_shift8 = (x + 40'sd128) >>> 8;
        else
            round_shift8 = -(((-x) + 40'sd128) >>> 8);
    end
endfunction

// =============================================================================
// 8.  Main FSM
// =============================================================================
integer jj;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= ST_IDLE;
        mel_idx        <= 5'd0;
        cep_idx        <= 4'd0;
        log_input_reg  <= 32'd0;
        log_result_reg <= 16'd0;
        dct_log_reg    <= 17'sd0;
        dct_coeff_reg  <= 16'sd0;
        dct_prod_reg   <= 33'sd0;
        dct_accum      <= 40'sd0;
        mfcc_coeff_out <= 32'sd0;
        mfcc_valid     <= 1'b0;
        mfcc_last      <= 1'b0;
        for (jj = 0; jj < NUM_MEL; jj = jj + 1)
            log_mel[jj] <= 16'd0;
    end else begin

        mfcc_valid <= 1'b0;
        mfcc_last  <= 1'b0;

        case (state)

            // One cycle to clear mel_accum, then immediately go to ACCUM
            ST_IDLE: begin
                mel_idx   <= 5'd0;
                cep_idx   <= 4'd0;
                dct_accum <= 40'sd0;
                state     <= ST_ACCUM_CAPTURE;
            end

            // Wait for CORDIC to push all bins through; mel_accum fills here
            ST_ACCUM_CAPTURE: begin
                if (mag_tvalid && mag_tlast) begin
                    mel_idx <= 5'd0;
                    state   <= ST_LOG_CAPTURE;
                end
            end

            // One cycle per Mel bank: register log?(mel_accum[i])
            ST_LOG_CAPTURE: begin
                log_input_reg <= mel_accum[mel_idx];
                state         <= ST_LOG_COMPUTE;
            end

            ST_LOG_COMPUTE: begin
                log_result_reg <= log_result_next;
                state          <= ST_LOG_WRITE;
            end

            ST_LOG_WRITE: begin
                log_mel[mel_idx] <= log_result_reg;
                if (mel_idx == NUM_MEL - 1) begin
                    mel_idx   <= 5'd0;
                    cep_idx   <= 4'd0;
                    dct_accum <= 40'sd0;
                    state     <= ST_DCT_CAPTURE;
                end else begin
                    mel_idx <= mel_idx + 5'd1;
                    state   <= ST_LOG_CAPTURE;
                end
            end

            // NUM_MEL MAC cycles per cepstral coefficient
            ST_DCT_CAPTURE: begin
                dct_log_reg <= {1'b0, log_mel[mel_idx][15:3]};  // >>3 before DCT
                dct_coeff_reg <= dct_cos_rom[dct_rom_addr_next];
                state         <= ST_DCT_MUL;
            end

            ST_DCT_MUL: begin
                dct_prod_reg <= dct_prod_next;
                state        <= ST_DCT_ACC;
            end

            ST_DCT_ACC: begin
                dct_accum <= (mel_idx == 5'd0)
                    ? {{7{dct_prod_reg[32]}}, dct_prod_reg}
                    : dct_accum + {{7{dct_prod_reg[32]}}, dct_prod_reg};

                if (mel_idx == NUM_MEL - 1) begin
                    mel_idx <= 5'd0;
                    state   <= ST_OUT;
                end else begin
                    mel_idx <= mel_idx + 5'd1;
                    state   <= ST_DCT_CAPTURE;
                end
            end

            // Emit one coefficient; loop back to DCT for next, or IDLE when done
            ST_OUT: begin
                mfcc_coeff_out <= round_shift8(dct_accum);
                mfcc_valid     <= 1'b1;

                if (cep_idx == NUM_CEP - 1) begin
                    mfcc_last <= 1'b1;
                    state     <= ST_IDLE;
                end else begin
                    cep_idx   <= cep_idx + 4'd1;
                    mel_idx   <= 5'd0;
                    dct_accum <= 40'sd0;
                    state     <= ST_DCT_CAPTURE;
                end
            end

            default: state <= ST_IDLE;
        endcase
    end
end
    assign dct_accum_probe = dct_accum;

endmodule
// =============================================================================
// End of mfcc_processor.v
// =============================================================================
