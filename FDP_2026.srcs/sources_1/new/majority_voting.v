`timescale 1ns / 1ps

// majority_voting.v
// Counts per-frame NN decisions. Resets on rst or auto_rst (uart_start_pulse).
// No longer auto-resets on NUM_FRAMES — the final result is determined externally
// in top.v when UART times out, using whatever counts have accumulated.
//
// SINDHU_BIAS: added to score_sindhu before comparison to compensate for the
// model's structural Kaushik bias (l2_bias gap gives Kaushik ~1 logit unit
// advantage; the larger SINDHU_BIAS corrects borderline misclassifications).
// Tune upward if Sindhu is still misidentified; downward if Kaushik degrades.
//
// COUNTER WIDTH NOTE:
//   Original 4s window: ~400 max votes → 8-bit counters (max 255, saturating) was sufficient.
//   New 8s analysis window: 16kHz audio, 160-sample hop = 100 frames/s → ~800 max NN inferences.
//   Both kaushik_count and sindhu_count are widened to 10 bits (max 1023, no saturation clamp
//   needed below 800). frame_count_out cap raised to 9'd800 accordingly.
//   top.v wire declarations for kcount/scount must also be [9:0].

module majority_voting (
    input  wire        clk,
    input  wire        rst,       // ~aresetn (global reset)
    input  wire        auto_rst,  // uart_start_pulse: clear for new UART session
    input  wire        nn_valid,
    input  wire signed [31:0] score_kaushik,
    input  wire signed [31:0] score_sindhu,
    input  wire [1:0]  sindhu_bias_sel,  // 00=0, 01=1, 10=2, 11=3
    output reg  [9:0]  kaushik_count,    // 10-bit: supports up to 1023 votes (8s window ~800 max)
    output reg  [9:0]  sindhu_count,     // 10-bit: same
    output reg  [9:0]  frame_count_out   // 10-bit progress counter, capped at 800
);

    reg signed [31:0] sindhu_bias;
    always @(*) begin
        case (sindhu_bias_sel)
            2'd0: sindhu_bias = 32'sd0;
            2'd1: sindhu_bias = 32'sd1;
            2'd2: sindhu_bias = 32'sd2;
            2'd3: sindhu_bias = 32'sd3;
        endcase
    end

    wire signed [31:0] score_sindhu_adj = score_sindhu + sindhu_bias;

    always @(posedge clk) begin
        if (rst || auto_rst) begin
            kaushik_count   <= 10'd0;
            sindhu_count    <= 10'd0;
            frame_count_out <= 10'd0;
        end else if (nn_valid) begin
            // Tally vote using bias-adjusted Sindhu score
            if (score_kaushik > score_sindhu_adj) begin
                if (kaushik_count < 10'd1023)
                    kaushik_count <= kaushik_count + 10'd1;
            end else begin
                if (sindhu_count < 10'd1023)
                    sindhu_count <= sindhu_count + 10'd1;
            end

            // Advance progress counter, cap at 800 (8s window at 100 inferences/s)
            if (frame_count_out < 10'd800)
                frame_count_out <= frame_count_out + 10'd1;
        end
    end

endmodule
