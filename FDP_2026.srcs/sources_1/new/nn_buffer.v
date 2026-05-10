`timescale 1ns / 1ps

// nn_input_buffer.v - 32-frame sliding window buffer for speaker NN
// Resets automatically on uart_start_pulse (new UART transmission detected).

module nn_input_buffer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        reset_window,     // 1-cycle pulse from top: new UART session

    // From mfcc_processor 
    input  wire signed [31:0] mfcc_coeff_out,
    input  wire        mfcc_valid,
    input  wire        mfcc_last,

    // To speaker_nn
    output reg  [13311:0] mfcc_window_flat,  // 32 x 13 x 32-bit
    output reg            nn_start,

    // Debug: high once 32-frame window is filled
    output wire           buffer_full_out
);

reg signed [31:0] frame_buf [0:11];
reg [3:0]         coeff_cnt   = 4'd0;
reg [4:0]         fill_cnt    = 5'd0;
reg               buffer_full = 1'b0;

assign buffer_full_out = buffer_full;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        coeff_cnt   <= 4'd0;
        fill_cnt    <= 5'd0;
        buffer_full <= 1'b0;
        nn_start    <= 1'b0;

    end else begin
        nn_start <= 1'b0;

        if (reset_window) begin
            coeff_cnt   <= 4'd0;
            fill_cnt    <= 5'd0;
            buffer_full <= 1'b0;

        end else if (mfcc_valid) begin
            if (mfcc_last) begin
                coeff_cnt <= 4'd0;

                // Slide: newest frame at MSB, oldest falls off LSB end.
                mfcc_window_flat <= {
                    mfcc_coeff_out,
                    frame_buf[11], frame_buf[10], frame_buf[9],
                    frame_buf[8],  frame_buf[7],  frame_buf[6],
                    frame_buf[5],  frame_buf[4],  frame_buf[3],
                    frame_buf[2],  frame_buf[1],  frame_buf[0],
                    mfcc_window_flat[13311:416]
                };

                if (!buffer_full) begin
                    if (fill_cnt == 5'd31) begin
                        buffer_full <= 1'b1;
                        nn_start    <= 1'b1;
                    end else begin
                        fill_cnt <= fill_cnt + 5'd1;
                    end
                end else begin
                    nn_start <= 1'b1;
                end

            end else begin
                frame_buf[coeff_cnt] <= mfcc_coeff_out;
                coeff_cnt            <= coeff_cnt + 4'd1;
            end
        end
    end
end

endmodule
