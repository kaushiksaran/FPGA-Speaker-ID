`timescale 1ns / 1ps

module FSK_T (
    input  [39:0] SW,       // 5 characters
    input         BTNC,
    input         basys3_clk,
    output reg [11:0] dac_data,
    output reg        dac_valid
);

    // High-freq tone (bit=1): 8 samples/cycle at 16kHz ~2000 Hz
    // Low-freq  tone (bit=0): 16 samples/cycle at 16kHz ~1000 Hz
    // Both use the same 8-entry sine LUT; low-freq advances phase every 2 samples.

    reg [11:0] sine_lut [0:7];
    initial begin
        sine_lut[0] = 12'd2048; sine_lut[1] = 12'd3495; sine_lut[2] = 12'd4000; sine_lut[3] = 12'd3495;
        sine_lut[4] = 12'd2048; sine_lut[5] = 12'd601;  sine_lut[6] = 12'd96;   sine_lut[7] = 12'd601;
    end

    reg [12:0] clk_div = 0;
    wire       tick_16k = (clk_div == 6249);
    always @(posedge basys3_clk) clk_div <= tick_16k ? 0 : clk_div + 1;

    reg [2:0] btn_sync = 0;
    always @(posedge basys3_clk) btn_sync <= {btn_sync[1:0], BTNC};
    wire btn_pulse = (btn_sync[2:1] == 2'b01);

    wire [15:0] lfsr0  = 16'hBEEF;
    wire [15:0] lfsr1  = {lfsr0[14:0],  lfsr0[15]  ^ lfsr0[13]  ^ lfsr0[11]  ^ lfsr0[0]};
    wire [15:0] lfsr2  = {lfsr1[14:0],  lfsr1[15]  ^ lfsr1[13]  ^ lfsr1[11]  ^ lfsr1[0]};
    wire [15:0] lfsr3  = {lfsr2[14:0],  lfsr2[15]  ^ lfsr2[13]  ^ lfsr2[11]  ^ lfsr2[0]};
    wire [15:0] lfsr4  = {lfsr3[14:0],  lfsr3[15]  ^ lfsr3[13]  ^ lfsr3[11]  ^ lfsr3[0]};
    wire [15:0] lfsr5  = {lfsr4[14:0],  lfsr4[15]  ^ lfsr4[13]  ^ lfsr4[11]  ^ lfsr4[0]};
    wire [15:0] lfsr6  = {lfsr5[14:0],  lfsr5[15]  ^ lfsr5[13]  ^ lfsr5[11]  ^ lfsr5[0]};
    wire [15:0] lfsr7  = {lfsr6[14:0],  lfsr6[15]  ^ lfsr6[13]  ^ lfsr6[11]  ^ lfsr6[0]};
    wire [15:0] lfsr8  = {lfsr7[14:0],  lfsr7[15]  ^ lfsr7[13]  ^ lfsr7[11]  ^ lfsr7[0]};
    wire [15:0] lfsr9  = {lfsr8[14:0],  lfsr8[15]  ^ lfsr8[13]  ^ lfsr8[11]  ^ lfsr8[0]};
    wire [15:0] lfsr10 = {lfsr9[14:0],  lfsr9[15]  ^ lfsr9[13]  ^ lfsr9[11]  ^ lfsr9[0]};
    wire [15:0] lfsr11 = {lfsr10[14:0], lfsr10[15] ^ lfsr10[13] ^ lfsr10[11] ^ lfsr10[0]};

    wire [39:0] key       = {lfsr11, lfsr11, lfsr11[15:8]};
    wire [39:0] encrypted = SW ^ key;
    wire [55:0] frame     = {8'b10101010, 8'b11111110, encrypted};

    localparam IDLE = 1'b0, SENDING = 1'b1;
    reg        state      = IDLE;
    reg [7:0]  sample_cnt = 0;
    reg [5:0]  bit_idx    = 0;
    reg [2:0]  phase      = 0;
    reg        phase_tick = 0;   // low-freq: advance phase every 2 samples
    reg        cur_bit    = 0;

    always @(posedge basys3_clk) begin
        dac_valid <= 1'b0;

        case (state)
        IDLE: begin
            dac_data  <= 12'd2048;
            phase     <= 0;
            phase_tick <= 0;
            if (btn_pulse) begin
                state      <= SENDING;
                bit_idx    <= 0;
                sample_cnt <= 0;
                cur_bit    <= frame[55];
            end
        end

        SENDING: begin
            if (tick_16k) begin
                dac_valid <= 1'b1;

                if (cur_bit) begin
                    // High freq: advance phase every sample (8 steps/cycle ~2000 Hz)
                    phase    <= phase + 1;
                    dac_data <= sine_lut[phase];
                end else begin
                    // Low freq: advance phase every 2 samples (16 steps/cycle ~1000 Hz)
                    if (phase_tick) begin
                        phase    <= phase + 1;
                        dac_data <= sine_lut[phase];
                    end else begin
                        dac_data <= sine_lut[phase];
                    end
                    phase_tick <= ~phase_tick;
                end

                if (sample_cnt == 159) begin
                    sample_cnt <= 0;
                    phase_tick <= 0;
                    if (bit_idx == 55) begin
                        state    <= IDLE;
                        dac_data <= 12'd2048;
                    end else begin
                        bit_idx <= bit_idx + 1;
                        cur_bit <= frame[54 - bit_idx];
                    end
                end else begin
                    sample_cnt <= sample_cnt + 1;
                end
            end
        end
        endcase
    end
endmodule
