`timescale 1ns / 1ps

//   - sw3 = enable_debug_overlay: live Sindhu/Kaushik count in S_ANALYZING
//   - sw1 = debug_force_sindhu: force auth_ok regardless of majority vote
//   - sw2 = debug_force_kaushik: force auth_denied regardless of majority vote
//     (sw1 and sw2 are labeled debug_force_auth in RTL; both OFF for normal NN operation)
//   - S_WELCOME shows "AUTH OK - SINDHU"
//   - S_DENIED shows "ACCESS DENIED - KAUSHIK"
//   - FSK TX/RX animations ported from spec

module top_level_ui (
    input clk, reset,
    input sw0, sw1, sw3,          
                                   
    input btnU, btnD, btnC, btnL, btnR,

    // UART activity triggers (synced into slow_clk domain by top.v)
    input uart_start,   // 1-cycle pulse: UART transmission began
    input uart_done,    // 1-cycle pulse: UART silence timeout

    // NN vote counts for pie chart overlay (10-bit, from widened majority_voting)
    input [9:0] kaushik_count,
    input [9:0] sindhu_count,

    input [191:0] fft_data_flat,
    input [51:0]  mfcc_data_flat,

    // FSK TX/RX — 40-bit (5 characters)
    output reg [39:0] tx_data,
    output reg        tx_trigger,
    input      [39:0] rx_data,
    input             rx_valid,

    output cs, sdin, sclk, d_cn, resn, vccen, pmoden
);

    // ==========================================
    // 1. STATE MACHINE
    // ==========================================
    localparam S_IDLE      = 4'd0;
    localparam S_ANALYZING = 4'd1;
    localparam S_DENIED    = 4'd2;
    localparam S_WELCOME   = 4'd3;
    localparam S_SENDING   = 4'd4;
    localparam S_RECEIVING = 4'd5;
    localparam S_TX_WAIT   = 4'd6;
    localparam S_TX_DONE   = 4'd7;
    localparam S_RX_DONE   = 4'd8;

    reg [3:0] state = S_IDLE;
    reg [27:0] timer = 0;

    // Timing constants for 6.25 MHz clock
    localparam TIME_1S = 28'd6250000;
    localparam TIME_2S = 28'd12500000;
    localparam TIME_3S = 28'd18750000;
    localparam TIME_4S = 28'd25000000;
    localparam TIME_5S = 28'd31250000;

    reg menu_sel = 0;
    reg auth_flag = 0;          // latched result: 1=Sindhu, 0=Kaushik
    reg bar_full  = 0;          // set on uart_done to jump loading bar to 100%

    // ==========================================
    // debug_force_auth:
    //   sw1 = debug_force_sindhu (force auth_ok / S_WELCOME)
    //   sw0 passed as sw1 here acts as debug_force_kaushik (force S_DENIED)
    //   Both OFF = NN determines the outcome normally.
    // ==========================================
    wire debug_force_sindhu   = sw1;   
    wire debug_force_kaushik  = sw0;   
    wire debug_overlay_enable = sw3;  

    // ==========================================
    // 21ms DIGITAL BUTTON DEBOUNCER
    // ==========================================
    reg [16:0] db_cnt = 0;
    wire db_tick = (db_cnt == 17'd0);
    reg [4:0] btn_samp0 = 0;
    reg [4:0] btn_samp1 = 0;

    wire btnU_press = db_tick && btn_samp0[4] && !btn_samp1[4];
    wire btnD_press = db_tick && btn_samp0[3] && !btn_samp1[3];
    wire btnC_press = db_tick && btn_samp0[2] && !btn_samp1[2];
    wire btnL_press = db_tick && btn_samp0[1] && !btn_samp1[1];
    wire btnR_press = db_tick && btn_samp0[0] && !btn_samp1[0];

    reg key_pg = 0; reg key_y = 0; reg [2:0] key_x = 0;
    reg [7:0] text_buf [0:4];
    reg [2:0] text_len = 0;
    reg [39:0] latched_rx_data;

    // 2-stage CDC for rx_valid 
    reg rx_sync_1 = 0;
    reg rx_sync_2 = 0;

    always @(posedge clk) begin
        if (reset) begin
            state          <= S_IDLE;
            timer          <= 0;
            menu_sel       <= 0;
            key_pg         <= 0;
            key_y          <= 0;
            key_x          <= 0;
            text_len       <= 0;
            tx_trigger     <= 0;
            latched_rx_data <= 0;
            rx_sync_1      <= 0;
            rx_sync_2      <= 0;
            db_cnt         <= 0;
            btn_samp0      <= 0;
            btn_samp1      <= 0;
            auth_flag      <= 0;
            bar_full       <= 0;
        end else begin
            rx_sync_1 <= rx_valid;
            rx_sync_2 <= rx_sync_1;

            db_cnt <= db_cnt + 1;
            if (db_tick) begin
                btn_samp0 <= {btnU, btnD, btnC, btnL, btnR};
                btn_samp1 <= btn_samp0;
            end

            timer      <= timer + 1;
            tx_trigger <= 0;

            // Latch uart_done bar-full and auth result while in S_ANALYZING
            if (uart_done && state == S_ANALYZING) begin
                bar_full  <= 1;
                // Determine auth result: debug_force overrides NN
                if (debug_force_sindhu)
                    auth_flag <= 1;
                else if (debug_force_kaushik)
                    auth_flag <= 0;
                else
                    auth_flag <= (sindhu_count > kaushik_count) ? 1'b1 : 1'b0;
            end

            if (rx_sync_2 && state == S_RECEIVING) begin
                latched_rx_data <= rx_data;
                state           <= S_RX_DONE;
                timer           <= 0;
            end else begin
                case (state)
                    // -------------------------------------------------------
                    // IDLE: wait for UART activity (uart_start) to begin analysis
                    // -------------------------------------------------------
                    S_IDLE: begin
                        bar_full  <= 0;
                        auth_flag <= 0;
                        if (uart_start) begin
                            state <= S_ANALYZING;
                            timer <= 0;
                        end
                    end

                    // -------------------------------------------------------
                    // ANALYZING: wait for uart_done (then bar is already full),
                    // then after a brief 1s display window move to result.
                    // If bar_full already set, jump to result after 1s display.
                    // -------------------------------------------------------
                    S_ANALYZING: begin
                        if (bar_full && timer >= TIME_1S) begin
                            if (auth_flag)
                                state <= S_WELCOME;
                            else
                                state <= S_DENIED;
                            timer <= 0;
                        end
                    end

                    // -------------------------------------------------------
                    // DENIED / WELCOME
                    // -------------------------------------------------------
                    S_DENIED: begin
                        if (timer >= TIME_5S) begin
                            state <= S_IDLE;
                            timer <= 0;
                        end
                    end

                    S_WELCOME: begin
                        if (btnL_press)
                            state <= S_IDLE;
                        else begin
                            if (btnU_press) menu_sel <= 0;
                            if (btnD_press) menu_sel <= 1;
                            if (btnC_press) begin
                                if (menu_sel == 0) begin
                                    state    <= S_SENDING;
                                    key_pg   <= 0;
                                    key_y    <= 0;
                                    key_x    <= 0;
                                    text_len <= 0;
                                end else begin
                                    state <= S_RECEIVING;
                                end
                            end
                        end
                    end

                    // -------------------------------------------------------
                    // SENDING keyboard
                    // -------------------------------------------------------
                    S_SENDING: begin
                        if (btnR_press) begin
                            if (key_x == 6) begin key_pg <= ~key_pg; key_x <= 0; end
                            else key_x <= key_x + 1;
                        end
                        if (btnL_press) begin
                            if (key_x == 0) begin key_pg <= ~key_pg; key_x <= 6; end
                            else key_x <= key_x - 1;
                        end
                        if (btnD_press || btnU_press) key_y <= ~key_y;

                        if (btnC_press) begin
                            if (key_pg == 0) begin
                                if (text_len < 5) begin
                                    if (key_y == 0) text_buf[text_len] <= 8'h41 + key_x;
                                    else            text_buf[text_len] <= 8'h48 + key_x;
                                    text_len <= text_len + 1;
                                end
                            end else begin
                                if (key_y == 0) begin
                                    if (text_len < 5) begin
                                        text_buf[text_len] <= 8'h4F + key_x;
                                        text_len <= text_len + 1;
                                    end
                                end else begin
                                    if (key_x < 5) begin
                                        if (text_len < 5) begin
                                            text_buf[text_len] <= 8'h56 + key_x;
                                            text_len <= text_len + 1;
                                        end
                                    end else if (key_x == 5) begin
                                        if (text_len > 0) text_len <= text_len - 1;
                                    end else if (key_x == 6) begin
                                        if (text_len > 0) begin
                                            // Pack all 5 chars, pad missing slots with space (0x20)
                                            tx_data <= {
                                                text_buf[0],
                                                (text_len > 1) ? text_buf[1] : 8'h20,
                                                (text_len > 2) ? text_buf[2] : 8'h20,
                                                (text_len > 3) ? text_buf[3] : 8'h20,
                                                (text_len > 4) ? text_buf[4] : 8'h20
                                            };
                                            tx_trigger <= 1'b1;
                                            timer      <= 0;
                                            state      <= S_TX_WAIT;
                                        end else begin
                                            state <= S_WELCOME;
                                        end
                                    end
                                end
                            end
                        end
                    end

                    S_TX_WAIT: begin
                        if (timer >= TIME_3S) begin state <= S_TX_DONE; timer <= 0; end
                    end

                    S_TX_DONE: begin
                        if (timer >= TIME_2S) begin state <= S_WELCOME; timer <= 0; end
                    end

                    S_RECEIVING: begin
                        if (btnL_press || btnC_press) state <= S_WELCOME;
                    end

                    S_RX_DONE: begin
                        if (timer >= TIME_4S || btnC_press || btnL_press) begin
                            state <= S_WELCOME;
                            timer <= 0;
                        end
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

    // ==========================================
    // 2. OLED HARDWARE DRIVER
    // ==========================================
    wire [12:0] current_pixel_index;
    wire sample_pixel_trigger;
    wire frame_begin_trigger;
    reg [15:0] color_to_send;

    OLED_Display my_screen (
        .clk        (clk),
        .reset      (reset),
        .frame_begin(frame_begin_trigger),
        .sample_pixel(sample_pixel_trigger),
        .pixel_index(current_pixel_index),
        .pixel_data (color_to_send),
        .cs(cs), .sdin(sdin), .sclk(sclk), .d_cn(d_cn),
        .resn(resn), .vccen(vccen), .pmoden(pmoden)
    );

    reg [6:0] pixel_x; reg [5:0] pixel_y;
    always @(posedge clk) begin
        if (frame_begin_trigger) begin pixel_x <= 0; pixel_y <= 0; end
        else if (sample_pixel_trigger) begin
            if (pixel_x == 95) begin pixel_x <= 0; pixel_y <= pixel_y + 1; end
            else pixel_x <= pixel_x + 1;
        end
    end

    // ==========================================
    // 3. GRAPHICS HELPERS
    // ==========================================
    wire [4:0] current_fft_bin = pixel_x / 3;
    wire [5:0] current_bin_magnitude = fft_data_flat[(current_fft_bin * 6) +: 6];

    // Loading bar: prog_width from timer (capped at full bar = 73 pixels wide, max timer ~TIME_8S)
    // When bar_full is set, force prog_width to full (73).
    wire [6:0] prog_width_live = (timer >> 21);  // ~73 at ~24s; bar_full jumps to full on uart_done
    wire [6:0] prog_width = bar_full ? 7'd73 : (prog_width_live > 7'd73 ? 7'd73 : prog_width_live);

    wire [4:0] rx_mag = (current_bin_magnitude > 28) ? 28 : current_bin_magnitude[4:0];

    reg [51:0] latched_mfcc_data;
    always @(posedge clk) begin
        if (frame_begin_trigger) latched_mfcc_data <= mfcc_data_flat;
    end
    wire [3:0] mfcc_idx = (pixel_x >= 2 && pixel_x <= 92) ? (pixel_x - 2) / 7 : 0;
    wire [3:0] current_mfcc_val = latched_mfcc_data[(mfcc_idx * 4) +: 4];
    reg [15:0] heat_color;
    always @(*) heat_color = {5'b00000, current_mfcc_val, 2'b00, 5'b00000};

    // ==========================================
    // FSK TX ANIMATION WIRES  (from spec)
    // ==========================================
    wire [4:0] tx_shrink_step = (timer > TIME_1S && timer < TIME_2S) ? ((timer - TIME_1S) >> 18) : 0;
    wire [6:0] tx_fly_step    = (timer > TIME_2S) ? ((timer - TIME_2S) >> 16) : 0;

    wire [7:0] tx_box_x1 = (timer < TIME_1S) ? 16 : (timer < TIME_2S) ? 16 + tx_shrink_step + (tx_shrink_step >> 2) : 45 + tx_fly_step;
    wire [7:0] tx_box_x2 = (timer < TIME_1S) ? 84 : (timer < TIME_2S) ? 84 - tx_shrink_step - (tx_shrink_step >> 2) : 57 + tx_fly_step;
    wire [6:0] tx_box_y1 = (timer < TIME_1S) ? 26 : (timer < TIME_2S) ? 26 + (tx_shrink_step >> 2) : 31;
    wire [6:0] tx_box_y2 = (timer < TIME_1S) ? 45 : (timer < TIME_2S) ? 45 - (tx_shrink_step >> 2) : 43;

    // ==========================================
    // FSK RX ANIMATION WIRES  (from spec)
    // ==========================================
    wire [6:0] rx_fly_step    = (timer < TIME_1S) ? (timer >> 17) : 47;
    wire [4:0] rx_grow_step   = (timer > TIME_1S && timer < TIME_2S) ? ((timer - TIME_1S) >> 18) : 0;

    wire [7:0] rx_box_x1 = (timer < TIME_1S) ? rx_fly_step : (timer < TIME_2S) ? 47 - rx_grow_step - (rx_grow_step >> 1) : 15;
    wire [7:0] rx_box_x2 = (timer < TIME_1S) ? 12 + rx_fly_step : (timer < TIME_2S) ? 59 + rx_grow_step : 81;
    wire [6:0] rx_box_y1 = (timer < TIME_1S) ? 31 : (timer < TIME_2S) ? 31 - (rx_grow_step >> 1) - (rx_grow_step >> 2) : 16;
    wire [6:0] rx_box_y2 = (timer < TIME_1S) ? 43 : (timer < TIME_2S) ? 43 + (rx_grow_step >> 2) + (rx_grow_step >> 3) : 48;

    // ==========================================
    // 4. GRAPHICS ENGINE & TEXT RENDERER
    // ==========================================
    reg [7:0]  char_to_draw; reg text_active; reg [6:0] text_x_start; reg [5:0] text_y_start;
    reg [15:0] text_color;   reg [6:0] char_idx; reg [2:0] char_x; reg [2:0] char_y; reg [34:0] font_data;

    wire [3:0] k_h = (kaushik_count >= 900) ? 4'd9 : (kaushik_count >= 800) ? 4'd8 :
                     (kaushik_count >= 700) ? 4'd7 : (kaushik_count >= 600) ? 4'd6 :
                     (kaushik_count >= 500) ? 4'd5 : (kaushik_count >= 400) ? 4'd4 :
                     (kaushik_count >= 300) ? 4'd3 : (kaushik_count >= 200) ? 4'd2 :
                     (kaushik_count >= 100) ? 4'd1 : 4'd0;
    // k_rem_h = kaushik_count - k_h*100: k_h*100 = k_h*64 + k_h*32 + k_h*4
    wire [9:0] k_h10 = {k_h, 6'b0} + {k_h, 5'b0} + {k_h, 2'b0}; // *100 via shifts
    wire [9:0] k_rem_h = kaushik_count - k_h10;
    wire [3:0] k_t = (k_rem_h >= 90) ? 4'd9 : (k_rem_h >= 80) ? 4'd8 :
                     (k_rem_h >= 70) ? 4'd7 : (k_rem_h >= 60) ? 4'd6 :
                     (k_rem_h >= 50) ? 4'd5 : (k_rem_h >= 40) ? 4'd4 :
                     (k_rem_h >= 30) ? 4'd3 : (k_rem_h >= 20) ? 4'd2 :
                     (k_rem_h >= 10) ? 4'd1 : 4'd0;
    // k_t*10 = k_t*8 + k_t*2
    wire [6:0] k_t10 = {k_t, 3'b0} + {k_t, 1'b0};
    wire [3:0] k_u = k_rem_h[3:0] - k_t10[3:0];

    wire [3:0] s_h = (sindhu_count >= 900) ? 4'd9 : (sindhu_count >= 800) ? 4'd8 :
                     (sindhu_count >= 700) ? 4'd7 : (sindhu_count >= 600) ? 4'd6 :
                     (sindhu_count >= 500) ? 4'd5 : (sindhu_count >= 400) ? 4'd4 :
                     (sindhu_count >= 300) ? 4'd3 : (sindhu_count >= 200) ? 4'd2 :
                     (sindhu_count >= 100) ? 4'd1 : 4'd0;
    wire [9:0] s_h10 = {s_h, 6'b0} + {s_h, 5'b0} + {s_h, 2'b0};
    wire [9:0] s_rem_h = sindhu_count - s_h10;
    wire [3:0] s_t = (s_rem_h >= 90) ? 4'd9 : (s_rem_h >= 80) ? 4'd8 :
                     (s_rem_h >= 70) ? 4'd7 : (s_rem_h >= 60) ? 4'd6 :
                     (s_rem_h >= 50) ? 4'd5 : (s_rem_h >= 40) ? 4'd4 :
                     (s_rem_h >= 30) ? 4'd3 : (s_rem_h >= 20) ? 4'd2 :
                     (s_rem_h >= 10) ? 4'd1 : 4'd0;
    wire [6:0] s_t10 = {s_t, 3'b0} + {s_t, 1'b0};
    wire [3:0] s_u = s_rem_h[3:0] - s_t10[3:0];

    always @(*) begin
        color_to_send = 16'h0000;
        text_active   = 0;
        text_x_start  = 0;
        text_y_start  = 0;
        text_color    = 16'hFFFF;
        char_to_draw  = 8'h20;
        char_idx      = 0;

        // --- LAYER 1: BACKGROUNDS ---
        case (state)
            S_IDLE: begin
                // Header bar y=0..11: dark green (matches bottom bar)
                if (pixel_y <= 11) color_to_send = 16'h0200;
                // FFT waveform y=12..50: 39 rows, with gap before bottom bar
                else if (pixel_y >= 12 && pixel_y <= 50) begin
                    if (pixel_x % 3 != 2) begin
                        if (pixel_y >= (50 - ((current_bin_magnitude > 38) ? 6'd38 : current_bin_magnitude[5:0]))) begin
                            if (pixel_y == (50 - ((current_bin_magnitude > 38) ? 6'd38 : current_bin_magnitude[5:0])))
                                color_to_send = 16'h07E0;
                            else
                                color_to_send = 16'h0120;
                        end
                    end
                end
                
                else if (pixel_y == 51) color_to_send = 16'h0000;
                else color_to_send = 16'h0200;
            end

            S_ANALYZING: begin
                // Loading bar outline — moved up: y=20..30, x=10..85
                if (pixel_y >= 20 && pixel_y <= 30 && pixel_x >= 10 && pixel_x <= 85) begin
                    if (pixel_y == 20 || pixel_y == 30 || pixel_x == 10 || pixel_x == 85)
                        color_to_send = 16'h0240;
                    else if ((pixel_x - 12) < prog_width && pixel_x >= 12 && pixel_x <= 83 &&
                             pixel_y >= 22 && pixel_y <= 28)
                        color_to_send = 16'h07E0;
                end
                // Normal mode: MFCC heatmap at bottom y=44..63
                if (!debug_overlay_enable && pixel_y >= 44 && pixel_y <= 63) begin
                    if (pixel_x >= 2 && pixel_x <= 92) begin
                        if ((pixel_x - 2) % 7 == 6 || pixel_y == 44 || pixel_y == 63)
                            color_to_send = 16'h0000;
                        else
                            color_to_send = heat_color;
                    end
                end
                // Debug mode (sw3): dark background for K/S count display y=34..63
                if (debug_overlay_enable && pixel_y >= 34) begin
                    color_to_send = 16'h0000;
                end
            end

            S_DENIED: begin
                if (pixel_y <= 11) color_to_send = 16'h2000;
                else if (pixel_y >= 39 && pixel_y <= 50) color_to_send = 16'h2000;
                else if (pixel_y >= 55 && pixel_y <= 60) begin
                    if (pixel_x >= 6  && pixel_x <= 18) color_to_send = 16'hF800;
                    else if (pixel_x >= 22 && pixel_x <= 34) color_to_send = (timer >= TIME_1S) ? 16'hF800 : 16'h4000;
                    else if (pixel_x >= 38 && pixel_x <= 50) color_to_send = (timer >= TIME_2S) ? 16'hF800 : 16'h4000;
                    else if (pixel_x >= 54 && pixel_x <= 66) color_to_send = (timer >= TIME_3S) ? 16'hF800 : 16'h4000;
                    else if (pixel_x >= 70 && pixel_x <= 82) color_to_send = (timer >= TIME_4S) ? 16'hF800 : 16'h4000;
                end
            end

            S_WELCOME: begin
                if (pixel_y >= 26 && pixel_y <= 42 && pixel_x >= 4 && pixel_x <= 91)
                    color_to_send = (menu_sel == 0) ? 16'h07E0 :
                                    ((pixel_y==26||pixel_y==42||pixel_x==4||pixel_x==91) ? 16'h0240 : 16'h0000);
                else if (pixel_y >= 44 && pixel_y <= 60 && pixel_x >= 4 && pixel_x <= 91)
                    color_to_send = (menu_sel == 1) ? 16'h07E0 :
                                    ((pixel_y==44||pixel_y==60||pixel_x==4||pixel_x==91) ? 16'h0240 : 16'h0000);
            end

            S_SENDING: begin
                if (pixel_y >= 1 && pixel_y <= 13 && pixel_x >= 2 && pixel_x <= 93) begin
                    if (pixel_y == 1 || pixel_y == 13 || pixel_x == 2 || pixel_x == 93)
                        color_to_send = 16'h0240;
                end
                if (pixel_x >= 2 && pixel_x <= 92) begin
                    char_idx = (pixel_x - 2) / 13;
                    if ((pixel_x - 2) % 13 < 11) begin
                        if (pixel_y >= 18 && pixel_y <= 31)
                            color_to_send = (key_y == 0 && key_x == char_idx) ? 16'h07E0 :
                                ((pixel_y==18||pixel_y==31||(pixel_x-2)%13==0||(pixel_x-2)%13==10) ? 16'h0240 : 16'h0000);
                        else if (pixel_y >= 35 && pixel_y <= 48)
                            color_to_send = (key_y == 1 && key_x == char_idx) ? 16'h07E0 :
                                ((pixel_y==35||pixel_y==48||(pixel_x-2)%13==0||(pixel_x-2)%13==10) ? 16'h0240 : 16'h0000);
                    end
                end
            end

            S_TX_WAIT: begin
                if (tx_box_x1 < 96 && pixel_y >= tx_box_y1 && pixel_y <= tx_box_y2 &&
                    pixel_x >= tx_box_x1 && pixel_x <= tx_box_x2) begin
                    color_to_send = 16'h0240;
                    if (pixel_y == tx_box_y1 || pixel_y == tx_box_y2 ||
                        pixel_x == tx_box_x1 || pixel_x == tx_box_x2)
                        color_to_send = 16'h07E0;
                    else if (timer >= TIME_1S && pixel_x == ((tx_box_x1 + tx_box_x2) >> 1))
                        color_to_send = 16'h0120;
                end
            end

            S_TX_DONE: begin
                if (pixel_y >= 22 && pixel_y <= 46 && pixel_x >= 10 && pixel_x <= 86) begin
                    color_to_send = 16'h0240;
                    if (pixel_y == 22 || pixel_y == 46 || pixel_x == 10 || pixel_x == 86)
                        color_to_send = 16'h07E0;
                end
            end

            S_RECEIVING: begin
                if (pixel_y < 10) color_to_send = 16'h0000;
                else if (pixel_y == 10) color_to_send = 16'h0240;
                else if (pixel_y >= 14 && pixel_y <= 42) begin
                    if (pixel_x % 3 != 2) begin
                        if (pixel_y >= (42 - rx_mag)) begin
                            if (pixel_y == (42 - rx_mag)) color_to_send = 16'h07E0;
                            else color_to_send = 16'h0120;
                        end
                    end
                end
            end

            S_RX_DONE: begin
                if (rx_box_x1 < 96 && pixel_y >= rx_box_y1 && pixel_y <= rx_box_y2 &&
                    pixel_x >= rx_box_x1 && pixel_x <= rx_box_x2) begin
                    color_to_send = 16'h0240;
                    if (pixel_y == rx_box_y1 || pixel_y == rx_box_y2 ||
                        pixel_x == rx_box_x1 || pixel_x == rx_box_x2)
                        color_to_send = 16'h07E0;
                    else if (timer < TIME_2S && pixel_x == ((rx_box_x1 + rx_box_x2) >> 1))
                        color_to_send = 16'h0120;
                end
            end
        endcase

        // --- LAYER 2: TEXT ENGINE ---
        case (state)
            S_IDLE: begin
                // "SYNAPSE" in header — black text on dark-green bar, y=2..9, x=2..44
                if (pixel_y >= 2 && pixel_y <= 9 && pixel_x >= 2 && pixel_x < 44) begin
                    text_active = 1; text_y_start = 2; text_x_start = 2; text_color = 16'h0000;
                    char_idx = (pixel_x - 2) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h53; // S
                        1: char_to_draw = 8'h59; // Y
                        2: char_to_draw = 8'h4E; // N
                        3: char_to_draw = 8'h41; // A
                        4: char_to_draw = 8'h50; // P
                        5: char_to_draw = 8'h53; // S
                        6: char_to_draw = 8'h45; // E
                        default: char_to_draw = 8'h20;
                    endcase
                end
                // "//UART TO START" on bottom bar — black text on green, matches header aesthetic
                else if (pixel_y >= 55 && pixel_y <= 62 && pixel_x >= 3 && pixel_x < 93) begin
                    text_active = 1; text_y_start = 55; text_x_start = 3; text_color = 16'h0000;
                    char_idx = (pixel_x - 3) / 6;
                    case (char_idx)
                        0:  char_to_draw = 8'h2F; // /
                        1:  char_to_draw = 8'h2F; // /
                        2:  char_to_draw = 8'h55; // U
                        3:  char_to_draw = 8'h41; // A
                        4:  char_to_draw = 8'h52; // R
                        5:  char_to_draw = 8'h54; // T
                        6:  char_to_draw = 8'h20; //
                        7:  char_to_draw = 8'h54; // T
                        8:  char_to_draw = 8'h4F; // O
                        9:  char_to_draw = 8'h20; //
                        10: char_to_draw = 8'h53; // S
                        11: char_to_draw = 8'h54; // T
                        12: char_to_draw = 8'h41; // A
                        13: char_to_draw = 8'h52; // R
                        14: char_to_draw = 8'h54; // T
                        default: char_to_draw = 8'h20;
                    endcase
                end
            end

            S_ANALYZING: begin
                // "ANALYZING" 
                if (pixel_y >= 2 && pixel_y <= 9 && pixel_x >= 21 && pixel_x < 75) begin
                    text_active = 1; text_y_start = 2; text_x_start = 21; text_color = 16'h07E0;
                    char_idx = (pixel_x - 21) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h41; 1: char_to_draw = 8'h4E; 2: char_to_draw = 8'h41;
                        3: char_to_draw = 8'h4C; 4: char_to_draw = 8'h59; 5: char_to_draw = 8'h5A;
                        6: char_to_draw = 8'h49; 7: char_to_draw = 8'h4E; 8: char_to_draw = 8'h47;
                        default: char_to_draw = 8'h20;
                    endcase
                end
                // "VOICE..." 
                else if (pixel_y >= 11 && pixel_y <= 18 && pixel_x >= 24 && pixel_x < 72) begin
                    text_active = 1; text_y_start = 11; text_x_start = 24; text_color = 16'h07E0;
                    char_idx = (pixel_x - 24) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h56; 1: char_to_draw = 8'h4F; 2: char_to_draw = 8'h49;
                        3: char_to_draw = 8'h43; 4: char_to_draw = 8'h45;
                        5: char_to_draw = (timer[23:22] >= 1) ? 8'h2E : 8'h20;
                        6: char_to_draw = (timer[23:22] >= 2) ? 8'h2E : 8'h20;
                        7: char_to_draw = (timer[23:22] >= 3) ? 8'h2E : 8'h20;
                        default: char_to_draw = 8'h20;
                    endcase
                end
                // Debug mode: "KAUSHIK" label y=36..43, red, x=4..45
                else if (debug_overlay_enable && pixel_y >= 36 && pixel_y <= 43 &&
                         pixel_x >= 4 && pixel_x < 46) begin
                    text_active = 1; text_y_start = 36; text_x_start = 4; text_color = 16'hF800;
                    char_idx = (pixel_x - 4) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h4B; 1: char_to_draw = 8'h41; 2: char_to_draw = 8'h55;
                        3: char_to_draw = 8'h53; 4: char_to_draw = 8'h48; 5: char_to_draw = 8'h49;
                        6: char_to_draw = 8'h4B; default: char_to_draw = 8'h20;
                    endcase
                end
                // Debug mode: "SINDHU" label y=36..43, green, x=52..93
                else if (debug_overlay_enable && pixel_y >= 36 && pixel_y <= 43 &&
                         pixel_x >= 52 && pixel_x < 94) begin
                    text_active = 1; text_y_start = 36; text_x_start = 52; text_color = 16'h07E0;
                    char_idx = (pixel_x - 52) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h53; 1: char_to_draw = 8'h49; 2: char_to_draw = 8'h4E;
                        3: char_to_draw = 8'h44; 4: char_to_draw = 8'h48; 5: char_to_draw = 8'h55;
                        default: char_to_draw = 8'h20;
                    endcase
                end
                // Debug mode: Kaushik count NNN y=46..53, red, x=10..27
                else if (debug_overlay_enable && pixel_y >= 46 && pixel_y <= 53 &&
                         pixel_x >= 10 && pixel_x < 28) begin
                    text_active = 1; text_y_start = 46; text_x_start = 10; text_color = 16'hF800;
                    char_idx = (pixel_x - 10) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h30 + k_h;
                        1: char_to_draw = 8'h30 + k_t;
                        2: char_to_draw = 8'h30 + k_u;
                        default: char_to_draw = 8'h20;
                    endcase
                end
                // Debug mode: Sindhu count NNN y=46..53, green, x=58..75
                else if (debug_overlay_enable && pixel_y >= 46 && pixel_y <= 53 &&
                         pixel_x >= 58 && pixel_x < 76) begin
                    text_active = 1; text_y_start = 46; text_x_start = 58; text_color = 16'h07E0;
                    char_idx = (pixel_x - 58) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h30 + s_h;
                        1: char_to_draw = 8'h30 + s_t;
                        2: char_to_draw = 8'h30 + s_u;
                        default: char_to_draw = 8'h20;
                    endcase
                end
                // Debug mode: "VS" divider at centre y=46..53, dim, x=44..55
                else if (debug_overlay_enable && pixel_y >= 46 && pixel_y <= 53 &&
                         pixel_x >= 44 && pixel_x < 56) begin
                    text_active = 1; text_y_start = 46; text_x_start = 44; text_color = 16'h0240;
                    char_idx = (pixel_x - 44) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h56; 1: char_to_draw = 8'h53; // VS
                        default: char_to_draw = 8'h20;
                    endcase
                end
                // Debug mode: "VOTES" footer y=56..63, dim, x=30..60
                else if (debug_overlay_enable && pixel_y >= 56 && pixel_y <= 63 &&
                         pixel_x >= 30 && pixel_x < 60) begin
                    text_active = 1; text_y_start = 56; text_x_start = 30; text_color = 16'h0240;
                    char_idx = (pixel_x - 30) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h56; 1: char_to_draw = 8'h4F; 2: char_to_draw = 8'h54;
                        3: char_to_draw = 8'h45; 4: char_to_draw = 8'h53;
                        default: char_to_draw = 8'h20;
                    endcase
                end
            end

            S_DENIED: begin
                // "! AUTH FAILED !" header
                if (pixel_y >= 2 && pixel_y <= 9 && pixel_x >= 3 && pixel_x < 93) begin
                    text_active = 1; text_y_start = 2; text_x_start = 3; text_color = 16'hA000;
                    char_idx = (pixel_x - 3) / 6;
                    case (char_idx)
                        0:  char_to_draw = 8'h21; 1:  char_to_draw = 8'h20; 2:  char_to_draw = 8'h41;
                        3:  char_to_draw = 8'h55; 4:  char_to_draw = 8'h54; 5:  char_to_draw = 8'h48;
                        6:  char_to_draw = 8'h20; 7:  char_to_draw = 8'h46; 8:  char_to_draw = 8'h41;
                        9:  char_to_draw = 8'h49; 10: char_to_draw = 8'h4C; 11: char_to_draw = 8'h45;
                        12: char_to_draw = 8'h44; 13: char_to_draw = 8'h20; 14: char_to_draw = 8'h21;
                        default: char_to_draw = 8'h20;
                    endcase
                end
                // "ACCESS"
                else if (pixel_y >= 16 && pixel_y <= 23 && pixel_x >= 30 && pixel_x < 66) begin
                    text_active = 1; text_y_start = 16; text_x_start = 30; text_color = 16'hF800;
                    char_idx = (pixel_x - 30) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h41; 1: char_to_draw = 8'h43; 2: char_to_draw = 8'h43;
                        3: char_to_draw = 8'h45; 4: char_to_draw = 8'h53; 5: char_to_draw = 8'h53;
                        default: char_to_draw = 8'h20;
                    endcase
                end
                // "DENIED"
                else if (pixel_y >= 26 && pixel_y <= 33 && pixel_x >= 30 && pixel_x < 66) begin
                    text_active = 1; text_y_start = 26; text_x_start = 30; text_color = 16'hF800;
                    char_idx = (pixel_x - 30) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h44; 1: char_to_draw = 8'h45; 2: char_to_draw = 8'h4E;
                        3: char_to_draw = 8'h49; 4: char_to_draw = 8'h45; 5: char_to_draw = 8'h44;
                        default: char_to_draw = 8'h20;
                    endcase
                end
                // "SPEAKER: KAUSHIK" 
                else if (pixel_y >= 41 && pixel_y <= 48 && pixel_x >= 0 && pixel_x < 96) begin
                    text_active = 1; text_y_start = 41; text_x_start = 0; text_color = 16'hA000;
                    char_idx = pixel_x / 6;
                    case (char_idx)
                        0:  char_to_draw = 8'h53; 1:  char_to_draw = 8'h50; 2:  char_to_draw = 8'h45;
                        3:  char_to_draw = 8'h41; 4:  char_to_draw = 8'h4B; 5:  char_to_draw = 8'h45;
                        6:  char_to_draw = 8'h52; 7:  char_to_draw = 8'h3A; 8:  char_to_draw = 8'h20;
                        9:  char_to_draw = 8'h4B; 10: char_to_draw = 8'h41; 11: char_to_draw = 8'h55;
                        12: char_to_draw = 8'h53; 13: char_to_draw = 8'h48; 14: char_to_draw = 8'h49;
                        15: char_to_draw = 8'h4B;
                        default: char_to_draw = 8'h20;
                    endcase
                end
            end

            S_WELCOME: begin
                // "AUTH OK" top left
                if (pixel_y >= 2 && pixel_y <= 9 && pixel_x >= 6 && pixel_x < 48) begin
                    text_active = 1; text_y_start = 2; text_x_start = 6; text_color = 16'h0240;
                    char_idx = (pixel_x - 6) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h41; 1: char_to_draw = 8'h55; 2: char_to_draw = 8'h54;
                        3: char_to_draw = 8'h48; 4: char_to_draw = 8'h20; 5: char_to_draw = 8'h4F;
                        6: char_to_draw = 8'h4B; default: char_to_draw = 8'h20;
                    endcase
                end
                // "SINDHU" authenticated user name
                else if (pixel_y >= 14 && pixel_y <= 21 && pixel_x >= 6 && pixel_x < 42) begin
                    text_active = 1; text_y_start = 14; text_x_start = 6; text_color = 16'h07E0;
                    char_idx = (pixel_x - 6) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h53; 1: char_to_draw = 8'h49; 2: char_to_draw = 8'h4E;
                        3: char_to_draw = 8'h44; 4: char_to_draw = 8'h48; 5: char_to_draw = 8'h55;
                        default: char_to_draw = 8'h20;
                    endcase
                end
                // [>] SEND  row
                else if (pixel_y >= 31 && pixel_y <= 38 && pixel_x >= 36 && pixel_x < 60) begin
                    text_active = 1; text_y_start = 31; text_x_start = 36;
                    text_color = (menu_sel==0) ? 16'h0000 : 16'h0240;
                    char_idx = (pixel_x - 36) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h53; 1: char_to_draw = 8'h45;
                        2: char_to_draw = 8'h4E; 3: char_to_draw = 8'h44;
                        default: char_to_draw = 8'h20;
                    endcase
                end
                else if (pixel_y >= 31 && pixel_y <= 38 && pixel_x >= 12 && pixel_x < 30) begin
                    text_active = 1; text_y_start = 31; text_x_start = 12;
                    text_color = (menu_sel==0) ? 16'h0000 : 16'h0240;
                    char_idx = (pixel_x - 12) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h5B;
                        1: char_to_draw = (menu_sel==0) ? 8'h3E : 8'h20;
                        2: char_to_draw = 8'h5D;
                        default: char_to_draw = 8'h20;
                    endcase
                end
                // [>] RECEIVE  row
                else if (pixel_y >= 49 && pixel_y <= 56 && pixel_x >= 36 && pixel_x < 78) begin
                    text_active = 1; text_y_start = 49; text_x_start = 36;
                    text_color = (menu_sel==1) ? 16'h0000 : 16'h0240;
                    char_idx = (pixel_x - 36) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h52; 1: char_to_draw = 8'h45; 2: char_to_draw = 8'h43;
                        3: char_to_draw = 8'h45; 4: char_to_draw = 8'h49; 5: char_to_draw = 8'h56;
                        6: char_to_draw = 8'h45; default: char_to_draw = 8'h20;
                    endcase
                end
                else if (pixel_y >= 49 && pixel_y <= 56 && pixel_x >= 12 && pixel_x < 30) begin
                    text_active = 1; text_y_start = 49; text_x_start = 12;
                    text_color = (menu_sel==1) ? 16'h0000 : 16'h0240;
                    char_idx = (pixel_x - 12) / 6;
                    case (char_idx)
                        0: char_to_draw = 8'h5B;
                        1: char_to_draw = (menu_sel==1) ? 8'h3E : 8'h20;
                        2: char_to_draw = 8'h5D;
                        default: char_to_draw = 8'h20;
                    endcase
                end
            end

            S_SENDING: begin
                // Text buffer preview
                if (pixel_y >= 4 && pixel_y <= 11 && pixel_x >= 4 && pixel_x <= 34) begin
                    char_idx = (pixel_x - 4) / 6;
                    if (char_idx < text_len) begin
                        text_active = 1; text_x_start = 4 + char_idx*6; text_y_start = 4;
                        text_color = 16'h07E0; char_to_draw = text_buf[char_idx];
                    end else if (char_idx == text_len && text_len < 5 && timer[23]) begin
                        text_active = 1; text_x_start = 4 + char_idx*6; text_y_start = 4;
                        text_color = 16'h07E0; char_to_draw = 8'h5F;
                    end
                end
                // Count display "N/5"
                if (pixel_y >= 4 && pixel_y <= 11 && pixel_x >= 70 && pixel_x <= 88) begin
                    text_active = 1; text_y_start = 4; text_color = 16'h07E0;
                    char_idx = (pixel_x - 70) / 6; text_x_start = 70 + char_idx*6;
                    if      (char_idx == 0) char_to_draw = 8'h30 + text_len;
                    else if (char_idx == 1) char_to_draw = 8'h2F;
                    else if (char_idx == 2) char_to_draw = 8'h35;
                end
                // Keyboard letters
                if (pixel_x >= 2 && pixel_x <= 92) begin
                    char_idx = (pixel_x - 2) / 13;
                    if ((pixel_x - 2) % 13 >= 3 && (pixel_x - 2) % 13 <= 7) begin
                        if (pixel_y >= 21 && pixel_y <= 28) begin
                            text_active = 1; text_x_start = 2 + char_idx*13 + 3; text_y_start = 21;
                            text_color = (key_y==0 && key_x==char_idx) ? 16'h0000 : 16'h0240;
                            if (key_pg == 0) char_to_draw = 8'h41 + char_idx;
                            else             char_to_draw = 8'h4F + char_idx;
                        end else if (pixel_y >= 38 && pixel_y <= 45) begin
                            text_active = 1; text_x_start = 2 + char_idx*13 + 3; text_y_start = 38;
                            text_color = (key_y==1 && key_x==char_idx) ? 16'h0000 : 16'h0240;
                            if (key_pg == 0) char_to_draw = 8'h48 + char_idx;
                            else begin
                                if      (char_idx < 5) char_to_draw = 8'h56 + char_idx;
                                else if (char_idx == 5) char_to_draw = 8'h3C;
                                else if (char_idx == 6) char_to_draw = 8'h3E;
                            end
                        end
                    end
                end
                // Page / DEL footer
                if (pixel_y >= 54 && pixel_y <= 61) begin
                    if (pixel_x >= 4 && pixel_x <= 38) begin
                        text_active = 1; text_y_start = 54; text_x_start = 4; text_color = 16'h0240;
                        char_idx = (pixel_x - 4) / 6;
                        case (char_idx)
                            0: char_to_draw = 8'h50; 1: char_to_draw = 8'h47;
                            2: char_to_draw = 8'h20; 3: char_to_draw = (key_pg==0) ? 8'h31 : 8'h32;
                            4: char_to_draw = 8'h2F; 5: char_to_draw = 8'h32;
                            default: char_to_draw = 8'h20;
                        endcase
                    end else if (pixel_x >= 64 && pixel_x <= 93) begin
                        text_active = 1; text_y_start = 54; text_x_start = 64; text_color = 16'h0240;
                        char_idx = (pixel_x - 64) / 6;
                        case (char_idx)
                            0: char_to_draw = 8'h3C; 1: char_to_draw = 8'h44;
                            2: char_to_draw = 8'h45; 3: char_to_draw = 8'h4C;
                            default: char_to_draw = 8'h20;
                        endcase
                    end
                end
            end

            S_TX_WAIT: begin
                if (timer < TIME_1S) begin
                    if (pixel_y >= 28 && pixel_y <= 35 && pixel_x >= 20 && pixel_x < 80) begin
                        text_active = 1; text_y_start = 28; text_x_start = 20; text_color = 16'h07E0;
                        char_idx = (pixel_x - 20) / 6;
                        case (char_idx)
                            0: char_to_draw = 8'h53; 1: char_to_draw = 8'h45; 2: char_to_draw = 8'h4E;
                            3: char_to_draw = 8'h44; 4: char_to_draw = 8'h49; 5: char_to_draw = 8'h4E;
                            6: char_to_draw = 8'h47;
                            7: char_to_draw = (timer[23:22]>=1) ? 8'h2E : 8'h20;
                            8: char_to_draw = (timer[23:22]>=2) ? 8'h2E : 8'h20;
                            9: char_to_draw = (timer[23:22]>=3) ? 8'h2E : 8'h20;
                            default: char_to_draw = 8'h20;
                        endcase
                    end else if (pixel_y >= 36 && pixel_y <= 43 && pixel_x >= 33 && pixel_x < 63) begin
                        char_idx = (pixel_x - 33) / 6;
                        if (char_idx < text_len) begin
                            text_active = 1; text_y_start = 36; text_x_start = 33;
                            text_color = 16'hFFFF; char_to_draw = text_buf[char_idx];
                        end
                    end
                end
            end

            S_TX_DONE: begin
                if (pixel_y >= 25 && pixel_y <= 32 && pixel_x >= 12 && pixel_x < 84) begin
                    text_active = 1; text_y_start = 25; text_x_start = 12; text_color = 16'h07E0;
                    char_idx = (pixel_x - 12) / 6;
                    case (char_idx)
                        0:char_to_draw=8'h53; 1:char_to_draw=8'h55; 2:char_to_draw=8'h43; 3:char_to_draw=8'h43;
                        4:char_to_draw=8'h45; 5:char_to_draw=8'h53; 6:char_to_draw=8'h53; 7:char_to_draw=8'h46;
                        8:char_to_draw=8'h55; 9:char_to_draw=8'h4C; 10:char_to_draw=8'h4C; 11:char_to_draw=8'h59;
                        default: char_to_draw = 8'h20;
                    endcase
                end else if (pixel_y >= 35 && pixel_y <= 42 && pixel_x >= 33 && pixel_x < 63) begin
                    text_active = 1; text_y_start = 35; text_x_start = 33; text_color = 16'h07E0;
                    char_idx = (pixel_x - 33) / 6;
                    case (char_idx)
                        0:char_to_draw=8'h53; 1:char_to_draw=8'h45; 2:char_to_draw=8'h4E;
                        3:char_to_draw=8'h54; 4:char_to_draw=8'h21; default: char_to_draw=8'h20;
                    endcase
                end
            end

            S_RECEIVING: begin
                // "RX MODE" header
                if (pixel_y >= 2 && pixel_y <= 9 && pixel_x >= 2 && pixel_x < 44) begin
                    text_active = 1; text_y_start = 2; text_x_start = 2; text_color = 16'h0240;
                    char_idx = (pixel_x - 2) / 6;
                    case (char_idx)
                        0:char_to_draw=8'h52; 1:char_to_draw=8'h58; 2:char_to_draw=8'h20;
                        3:char_to_draw=8'h4D; 4:char_to_draw=8'h4F; 5:char_to_draw=8'h44;
                        6:char_to_draw=8'h45; default: char_to_draw=8'h20;
                    endcase
                end
                // "HUNTING" with animated dots
                if (pixel_y >= 2 && pixel_y <= 9 && pixel_x >= 54 && pixel_x < 96) begin
                    text_active = 1; text_y_start = 2; text_x_start = 54; text_color = 16'h07E0;
                    char_idx = (pixel_x - 54) / 6;
                    case (char_idx)
                        0:char_to_draw=8'h48; 1:char_to_draw=8'h55; 2:char_to_draw=8'h4E;
                        3:char_to_draw=8'h54; 4:char_to_draw=8'h49; 5:char_to_draw=8'h4E;
                        6:char_to_draw=8'h47; default: char_to_draw=8'h20;
                    endcase
                end
                else if (pixel_y >= 46 && pixel_y <= 53 && pixel_x >= 18 && pixel_x < 78) begin
                    text_active = 1; text_y_start = 46; text_x_start = 18; text_color = 16'h07E0;
                    char_idx = (pixel_x - 18) / 6;
                    case (char_idx)
                        0:char_to_draw=8'h48; 1:char_to_draw=8'h55; 2:char_to_draw=8'h4E;
                        3:char_to_draw=8'h54; 4:char_to_draw=8'h49; 5:char_to_draw=8'h4E;
                        6:char_to_draw=8'h47;
                        7:char_to_draw=(timer[23:22]>=1)?8'h2E:8'h20;
                        8:char_to_draw=(timer[23:22]>=2)?8'h2E:8'h20;
                        9:char_to_draw=(timer[23:22]>=3)?8'h2E:8'h20;
                        default: char_to_draw=8'h20;
                    endcase
                end
                else if (pixel_y >= 56 && pixel_y <= 63 && pixel_x >= 15 && pixel_x < 81) begin
                    text_active = 1; text_y_start = 56; text_x_start = 15; text_color = 16'h0240;
                    char_idx = (pixel_x - 15) / 6;
                    case (char_idx)
                        0:char_to_draw=8'h53; 1:char_to_draw=8'h43; 2:char_to_draw=8'h41;
                        3:char_to_draw=8'h4E; 4:char_to_draw=8'h4E; 5:char_to_draw=8'h49;
                        6:char_to_draw=8'h4E; 7:char_to_draw=8'h47;
                        8:char_to_draw=(timer[23:22]>=1)?8'h2E:8'h20;
                        9:char_to_draw=(timer[23:22]>=2)?8'h2E:8'h20;
                        10:char_to_draw=(timer[23:22]>=3)?8'h2E:8'h20;
                        default: char_to_draw=8'h20;
                    endcase
                end
            end

            S_RX_DONE: begin
                if (timer >= TIME_2S) begin
                    if (pixel_y >= 20 && pixel_y <= 27 && pixel_x >= 20 && pixel_x < 74) begin
                        text_active = 1; text_y_start = 20; text_x_start = 20; text_color = 16'h07E0;
                        char_idx = (pixel_x - 20) / 6;
                        case (char_idx)
                            0:char_to_draw=8'h52; 1:char_to_draw=8'h45; 2:char_to_draw=8'h43;
                            3:char_to_draw=8'h45; 4:char_to_draw=8'h49; 5:char_to_draw=8'h56;
                            6:char_to_draw=8'h45; 7:char_to_draw=8'h44; 8:char_to_draw=8'h3A;
                            default: char_to_draw=8'h20;
                        endcase
                    end else if (pixel_y >= 36 && pixel_y <= 43 && pixel_x >= 33 && pixel_x < 63) begin
                        text_active = 1; text_y_start = 36; text_x_start = 33; text_color = 16'hFFFF;
                        char_idx = (pixel_x - 33) / 6;
                        case (char_idx)
                            0: char_to_draw = latched_rx_data[39:32];
                            1: char_to_draw = latched_rx_data[31:24];
                            2: char_to_draw = latched_rx_data[23:16];
                            3: char_to_draw = latched_rx_data[15:8];
                            4: char_to_draw = latched_rx_data[7:0];
                            default: char_to_draw = 8'h20;
                        endcase
                    end
                end
            end
        endcase

        // --- LAYER 3: FONT ROM ---
        if (text_active) begin
            char_x = (pixel_x - text_x_start) % 6;
            char_y = pixel_y - text_y_start;
            font_data = 35'b0;
            case (char_to_draw)
                8'h41: font_data=35'b01110_10001_10001_11111_10001_10001_10001; // A
                8'h42: font_data=35'b11110_10001_10001_11110_10001_10001_11110; // B
                8'h43: font_data=35'b01110_10001_10000_10000_10000_10001_01110; // C
                8'h44: font_data=35'b11110_10001_10001_10001_10001_10001_11110; // D
                8'h45: font_data=35'b11111_10000_10000_11110_10000_10000_11111; // E
                8'h46: font_data=35'b11111_10000_10000_11110_10000_10000_10000; // F
                8'h47: font_data=35'b01110_10001_10000_10111_10001_10001_01110; // G
                8'h48: font_data=35'b10001_10001_10001_11111_10001_10001_10001; // H
                8'h49: font_data=35'b01110_00100_00100_00100_00100_00100_01110; // I
                8'h4A: font_data=35'b00111_00010_00010_00010_10010_10010_01100; // J
                8'h4B: font_data=35'b10001_10010_10100_11000_10100_10010_10001; // K
                8'h4C: font_data=35'b10000_10000_10000_10000_10000_10000_11111; // L
                8'h4D: font_data=35'b10001_11011_10101_10001_10001_10001_10001; // M
                8'h4E: font_data=35'b10001_11001_10101_10101_10011_10001_10001; // N
                8'h4F: font_data=35'b01110_10001_10001_10001_10001_10001_01110; // O
                8'h50: font_data=35'b11110_10001_10001_11110_10000_10000_10000; // P
                8'h51: font_data=35'b01110_10001_10001_10001_10101_10010_01101; // Q
                8'h52: font_data=35'b11110_10001_10001_11110_10100_10010_10001; // R
                8'h53: font_data=35'b01111_10000_10000_01110_00001_00001_11110; // S
                8'h54: font_data=35'b11111_00100_00100_00100_00100_00100_00100; // T
                8'h55: font_data=35'b10001_10001_10001_10001_10001_10001_01110; // U
                8'h56: font_data=35'b10001_10001_10001_10001_10001_01010_00100; // V
                8'h57: font_data=35'b10001_10001_10001_10101_10101_11011_10001; // W
                8'h58: font_data=35'b10001_10001_01010_00100_01010_10001_10001; // X
                8'h59: font_data=35'b10001_10001_10001_01010_00100_00100_00100; // Y
                8'h5A: font_data=35'b11111_00001_00010_00100_01000_10000_11111; // Z
                8'h30: font_data=35'b01110_10001_10011_10101_11001_10001_01110; // 0
                8'h31: font_data=35'b00100_01100_00100_00100_00100_00100_01110; // 1
                8'h32: font_data=35'b01110_10001_00001_00110_01000_10000_11111; // 2
                8'h33: font_data=35'b11111_00010_00100_00010_00001_10001_01110; // 3
                8'h34: font_data=35'b00010_00110_01010_10010_11111_00010_00010; // 4
                8'h35: font_data=35'b11111_10000_11110_00001_00001_10001_01110; // 5
                8'h36: font_data=35'b01110_10000_10000_11110_10001_10001_01110; // 6
                8'h37: font_data=35'b11111_00001_00010_00100_01000_01000_01000; // 7
                8'h38: font_data=35'b01110_10001_10001_01110_10001_10001_01110; // 8
                8'h39: font_data=35'b01110_10001_10001_01111_00001_00001_01110; // 9
                8'h5B: font_data=35'b01110_01000_01000_01000_01000_01000_01110; // [
                8'h5D: font_data=35'b01110_00010_00010_00010_00010_00010_01110; // ]
                8'h3C: font_data=35'b00010_00100_01000_10000_01000_00100_00010; // <
                8'h3E: font_data=35'b10000_01000_00100_00010_00100_01000_10000; // >
                8'h2F: font_data=35'b00001_00010_00100_01000_10000_10000_00000; // /
                8'h5F: font_data=35'b00000_00000_00000_00000_00000_00000_11111; // _
                8'h2E: font_data=35'b00000_00000_00000_00000_00000_01100_01100; // .
                8'h2D: font_data=35'b00000_00000_00000_11111_00000_00000_00000; // -
                8'h3A: font_data=35'b00000_01100_01100_00000_01100_01100_00000; // :
                8'h21: font_data=35'b01100_01100_01100_01100_00000_01100_01100; // !
                default: font_data=35'b0;
            endcase
            if (char_x < 5 && char_y < 7 && font_data[34 - (char_y * 5 + char_x)])
                color_to_send = text_color;
        end
    end

endmodule
