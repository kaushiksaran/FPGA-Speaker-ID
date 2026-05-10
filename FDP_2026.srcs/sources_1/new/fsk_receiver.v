`timescale 1ns / 1ps

// Two-tone FSK (1000 Hz = bit 0, 2000 Hz = bit 1)
// Dual IIR envelope detectors tuned to each frequency.
// Decision: bit = 1 if env_hi > env_lo, else bit = 0.
// Frame sync unchanged: preamble 10101010 + start 11111110 + 40 payload bits.

module fsk_receiver (
    input             clk,
    input             rst,

    input      [11:0] sample,
    input             sample_rdy,

    // sw[14:13]: sensitivity profile
    input      [1:0]  sensitivity,

    output reg [39:0] decoded_data,
    output reg        data_valid,
    output reg [15:0] rx_msg_counter
);

    // ==========================================
    // 1. SENSITIVITY PROFILES
    // env_thresh: minimum gap between env_hi and env_lo to trust the decision.
    // deadzone:   minimum abs_diff to count as real signal energy.
    // ==========================================
    reg [11:0] deadzone;
    reg [19:0] env_thresh;

    always @(*) begin
        case (sensitivity)
            2'b00: begin deadzone = 12'd15; env_thresh = 20'd300;  end // Normal
            2'b01: begin deadzone = 12'd8;  env_thresh = 20'd100;  end // High Sensitivity
            2'b10: begin deadzone = 12'd30; env_thresh = 20'd800;  end // Noise Reject
            2'b11: begin deadzone = 12'd4;  env_thresh = 20'd50;   end // Debug / Max
        endcase
    end

    // ==========================================
    // 2. HIGH-FREQ ENERGY (~2000 Hz)
    //    Fast diff: consecutive sample difference.
    //    A 2000 Hz tone at 16kHz has 8 samples/cycle large fast diffs.
    //    A 1000 Hz tone has 16 samples/cycle slower, smaller fast diffs.
    // ==========================================
    reg [11:0] prev1 = 0;
    always @(posedge clk) begin
        if (sample_rdy) prev1 <= sample;
    end

    wire signed [12:0] diff_hi  = $signed({1'b0, sample}) - $signed({1'b0, prev1});
    wire [11:0]        abs_hi   = diff_hi[12] ? -diff_hi : diff_hi;
    wire [11:0]        rect_hi  = (abs_hi > deadzone) ? (abs_hi - deadzone) : 12'd0;

    reg [19:0] env_hi = 0;
    always @(posedge clk) begin
        if (rst) env_hi <= 0;
        else if (sample_rdy)
            env_hi <= env_hi - (env_hi >> 4) + rect_hi;
    end

    // ==========================================
    // 3. LOW-FREQ ENERGY (~1000 Hz)
    //    2-sample stride diff: captures slower half-cycles.
    //    A 1000 Hz tone at 16kHz = 16 samples/cycle; peak diff occurs every ~8 samples.
    //    A 2000 Hz tone averages out over 2 samples (partial cancellation).
    // ==========================================
    reg [11:0] prev2 = 0;   // sample from 2 steps ago
    reg [11:0] prev2_buf = 0;
    always @(posedge clk) begin
        if (sample_rdy) begin
            prev2_buf <= sample;
            prev2     <= prev2_buf;
        end
    end

    wire signed [12:0] diff_lo  = $signed({1'b0, sample}) - $signed({1'b0, prev2});
    wire [11:0]        abs_lo   = diff_lo[12] ? -diff_lo : diff_lo;
    wire [11:0]        rect_lo  = (abs_lo > deadzone) ? (abs_lo - deadzone) : 12'd0;

    reg [19:0] env_lo = 0;
    always @(posedge clk) begin
        if (rst) env_lo <= 0;
        else if (sample_rdy)
            env_lo <= env_lo - (env_lo >> 4) + rect_lo;
    end

    // ==========================================
    // 4. BIT DECISION
    //    bit_val=1 if hi-freq envelope dominates by at least env_thresh.
    //    bit_val=0 if lo-freq envelope dominates by at least env_thresh.
    //    Ambiguous (within threshold margin) hold previous bit.
    // ==========================================
    reg bit_val     = 0;
    reg prev_bit_val = 0;

    always @(posedge clk) begin
        if (rst) begin
            bit_val <= 0;
        end else if (sample_rdy) begin
            prev_bit_val <= bit_val;
            if (env_hi > env_lo + env_thresh)
                bit_val <= 1;
            else if (env_lo > env_hi + env_thresh)
                bit_val <= 0;
            // else hold ambiguous, keep last value
        end
    end

    // ==========================================
    // 5. LFSR DECRYPTION KEY (identical to transmitter)
    // ==========================================
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

    wire [39:0] key = {lfsr11, lfsr11, lfsr11[15:8]};

    // ==========================================
    // 6. FRAME SYNCHRONIZER (unchanged protocol)
    //    S_IDLE: wait for rising edge on bit_val (silence tone detected)
    //    S_HUNT: clock in bits, watch for start byte 11111110
    //    S_RECEIVE: clock in 40 payload bits
    // ==========================================
    localparam SAMP_PER_BIT = 160;
    localparam S_IDLE = 2'd0, S_HUNT = 2'd1, S_RECEIVE = 2'd2;

    reg [1:0]  state        = S_IDLE;
    reg [7:0]  bit_timer    = 0;
    reg [15:0] det_reg      = 0;
    reg [39:0] pay_reg      = 0;
    reg [5:0]  bit_cnt      = 0;
    reg [5:0]  hunt_timeout = 0;

    always @(posedge clk) begin
        if (rst) begin
            state          <= S_IDLE;
            rx_msg_counter <= 16'd0;
            data_valid     <= 1'b0;
            decoded_data   <= 40'd0;
            bit_timer      <= 8'd0;
            det_reg        <= 16'd0;
            hunt_timeout   <= 6'd0;
        end else begin
            data_valid <= 1'b0;

            if (sample_rdy) begin
                case (state)
                S_IDLE: begin
                    // Wait for a clean rising edge:
                    if (bit_val == 1'b1 && prev_bit_val == 1'b0) begin
                        state        <= S_HUNT;
                        bit_timer    <= (SAMP_PER_BIT / 2);  // phase-centre on first bit
                        det_reg      <= 16'd0;
                        hunt_timeout <= 6'd0;
                    end
                end

                S_HUNT: begin
                    if (bit_timer == SAMP_PER_BIT - 1) begin
                        bit_timer    <= 8'd0;
                        det_reg      <= {det_reg[14:0], bit_val};
                        hunt_timeout <= hunt_timeout + 1;

                        if ({det_reg[6:0], bit_val} == 8'b11111110) begin
                            state   <= S_RECEIVE;
                            bit_cnt <= 6'd0;
                            pay_reg <= 40'd0;
                        end else if (hunt_timeout >= 45) begin
                            state <= S_IDLE;
                        end
                    end else begin
                        bit_timer <= bit_timer + 1;
                    end
                end

                S_RECEIVE: begin
                    if (bit_timer == SAMP_PER_BIT - 1) begin
                        bit_timer <= 8'd0;
                        pay_reg   <= {pay_reg[38:0], bit_val};
                        bit_cnt   <= bit_cnt + 1;

                        if (bit_cnt == 6'd39) begin
                            decoded_data   <= {pay_reg[38:0], bit_val} ^ key;
                            data_valid     <= 1'b1;
                            rx_msg_counter <= rx_msg_counter + 1;
                            state          <= S_IDLE;
                        end
                    end else begin
                        bit_timer <= bit_timer + 1;
                    end
                end
                endcase
            end
        end
    end
endmodule
