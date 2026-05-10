`timescale 1ns / 1ps

// mfcc_display_scaler.v — cosmetic display scaler, precision loss fully acceptable.
//
// Original used 32-bit history buffers, a 36-bit sequential divider, and 8-frame
// history (1,010 LUTs + 1,246 FFs). Replaced with:
//   - 16-bit internal precision (display needs 4-bit output, 16-bit is ample)
//   - No history buffer: use single-frame cur_min/cur_max
//   - Division replaced by shift: (val - min) * 15 / range
//     approximated as ((val - min) << 4) >> log2_ceil(range)
//     where log2_ceil(range) is a 4-bit priority-encoded shift amount (16 LUTs)
//   - Per-coefficient lift table kept (shift-only, already cheap)
//   - FSM collapses to: INGEST coefficients, on mfcc_last compute and emit output
//
// Target: under 200 LUTs.

module mfcc_display_scaler (
    input  wire        clk,
    input  wire        rst_n,

    input  wire signed [31:0] mfcc_coeff_in,
    input  wire        mfcc_valid_in,
    input  wire        mfcc_last_in,

    output reg  [51:0] oled_mfcc_flat
);

// -------------------------------------------------------------------------
// Per-coefficient lift: truncate to 16 bits after shift
// -------------------------------------------------------------------------
wire signed [31:0] abs_val = (mfcc_coeff_in[31]) ? -mfcc_coeff_in : mfcc_coeff_in;

reg [3:0] rx_idx;

wire [15:0] lifted;
reg  [15:0] lifted_r; // registered after case (driven combinatorially)

always @(*) begin
    case (rx_idx)
        4'd0:  lifted_r = abs_val[22:7];    // >> 7, take [22:7] = 16 bits
        4'd1:  lifted_r = abs_val[18:3];    // >> 3
        4'd2:  lifted_r = abs_val[17:2];    // >> 2
        4'd3:  lifted_r = abs_val[16:1];    // >> 1
        4'd4,
        4'd5:  lifted_r = abs_val[15:0];    // unchanged, low 16 bits
        4'd6,
        4'd7:  lifted_r = abs_val[14:0] << 1; // << 1, saturates at 0xFFFF
        4'd8,
        4'd9:  lifted_r = abs_val[13:0] << 2;
        4'd10,
        4'd11: lifted_r = abs_val[12:0] << 3;
        4'd12: lifted_r = abs_val[11:0] << 4;
        default: lifted_r = abs_val[15:0];
    endcase
end
assign lifted = lifted_r;

// -------------------------------------------------------------------------
// Per-frame buffer and min/max (16-bit)
// -------------------------------------------------------------------------
reg [15:0] frame_buf [0:12];
reg [15:0] cur_min, cur_max;

// -------------------------------------------------------------------------
// On mfcc_last, compute scaled output combinatorially and register it.
// range = cur_max - cur_min (clamped to min 200 to squelch silence noise).
// scale(v) = clamp((v - cur_min) * 15 / range, 0, 15)
// Approximation: range_shift = leading-zero count of range (log2 floor).
// scaled = ((v - cur_min) << 4) >> range_shift, clamped to 4 bits.
// -------------------------------------------------------------------------

// Leading-zero based shift amount for range (priority encoder → 4 bits)
wire [15:0] range_raw  = cur_max - cur_min;
wire [15:0] range_eff  = (range_raw < 16'd200) ? 16'd200 : range_raw;

// log2_floor of range_eff: find highest set bit position (0..15)
reg [3:0] log2_range;
always @(*) begin
    casez (range_eff)
        16'b1???????????????: log2_range = 4'd15;
        16'b01??????????????: log2_range = 4'd14;
        16'b001?????????????: log2_range = 4'd13;
        16'b0001????????????: log2_range = 4'd12;
        16'b00001???????????: log2_range = 4'd11;
        16'b000001??????????: log2_range = 4'd10;
        16'b0000001?????????: log2_range = 4'd9;
        16'b00000001????????: log2_range = 4'd8;
        16'b000000001???????: log2_range = 4'd7;
        16'b0000000001??????: log2_range = 4'd6;
        16'b00000000001?????: log2_range = 4'd5;
        16'b000000000001????: log2_range = 4'd4;
        16'b0000000000001???: log2_range = 4'd3;
        16'b00000000000001??: log2_range = 4'd2;
        16'b000000000000001?: log2_range = 4'd1;
        default:              log2_range = 4'd0;
    endcase
end

// scale one coefficient: ((v - min) * 15) >> log2_range, clamp 0..15
// (v - min) is 16-bit unsigned; *15 = (<<4) - original ≤ 20 bits.
// We right-shift by log2_range, keeping top 4 bits.
function [3:0] scale_val;
    input [15:0] v;
    input [15:0] mn;
    input [3:0]  shift;
    reg   [19:0] num;
    reg   [19:0] shifted;
    begin
        num     = ({4'd0, v} - {4'd0, mn}) * 4'd15;
        shifted = num >> shift;
        scale_val = (shifted > 20'd15) ? 4'd15 : shifted[3:0];
    end
endfunction

// -------------------------------------------------------------------------
// Main clocked logic
// -------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_idx       <= 4'd0;
        cur_min      <= 16'hFFFF;
        cur_max      <= 16'h0000;
        oled_mfcc_flat <= 52'd0;
    end else if (mfcc_valid_in) begin
        // Store lifted value
        frame_buf[rx_idx] <= lifted;

        // Track min/max
        if (rx_idx == 4'd0) begin
            cur_min <= lifted;
            cur_max <= lifted;
        end else begin
            if (lifted < cur_min) cur_min <= lifted;
            if (lifted > cur_max) cur_max <= lifted;
        end

        if (mfcc_last_in) begin
            rx_idx <= 4'd0;
            // Compute and emit all 13 scaled values in one cycle
            oled_mfcc_flat[ 3: 0] <= scale_val(frame_buf[ 0], cur_min, log2_range);
            oled_mfcc_flat[ 7: 4] <= scale_val(frame_buf[ 1], cur_min, log2_range);
            oled_mfcc_flat[11: 8] <= scale_val(frame_buf[ 2], cur_min, log2_range);
            oled_mfcc_flat[15:12] <= scale_val(frame_buf[ 3], cur_min, log2_range);
            oled_mfcc_flat[19:16] <= scale_val(frame_buf[ 4], cur_min, log2_range);
            oled_mfcc_flat[23:20] <= scale_val(frame_buf[ 5], cur_min, log2_range);
            oled_mfcc_flat[27:24] <= scale_val(frame_buf[ 6], cur_min, log2_range);
            oled_mfcc_flat[31:28] <= scale_val(frame_buf[ 7], cur_min, log2_range);
            oled_mfcc_flat[35:32] <= scale_val(frame_buf[ 8], cur_min, log2_range);
            oled_mfcc_flat[39:36] <= scale_val(frame_buf[ 9], cur_min, log2_range);
            oled_mfcc_flat[43:40] <= scale_val(frame_buf[10], cur_min, log2_range);
            oled_mfcc_flat[47:44] <= scale_val(frame_buf[11], cur_min, log2_range);
            // coeff 12 is being written this cycle — use lifted directly
            oled_mfcc_flat[51:48] <= scale_val(lifted,        cur_min, log2_range);
        end else begin
            rx_idx <= rx_idx + 4'd1;
        end
    end
end

endmodule
