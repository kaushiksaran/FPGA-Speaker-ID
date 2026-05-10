`timescale 1ns / 1ps

module top(
    input  wire        clk,          
    input  wire        reset_btn,     

    // UART audio input 
    input  wire        uart_rx,

    // SPI microphone 
    input  wire        miso,
    output wire        mic_cs,
    output wire        mic_sclk,

    // Switches & buttons for UI
    input  wire [15:0] sw,
    input  wire        btnU, btnD, btnC, btnL, btnR,

    // LEDs (VU meter driven by SPI mic)
    output wire [15:0] led,

    // OLED (Pmod OLEDrgb on JB)
    output wire        oled_cs,
    output wire        oled_sdin,
    output wire        oled_sclk,
    output wire        oled_d_cn,
    output wire        oled_resn,
    output wire        oled_vccen,
    output wire        oled_pmoden,

    // FSK transmit: DA2 DAC on JC
    output wire        dac_sync_n,
    output wire        dac_mosi,
    output wire        dac_sclk_out
);

    // ==========================================
    // 0. Global Reset
    // ==========================================
    wire aresetn = ~reset_btn;

    // ==========================================
    // 1. 6.25 MHz slow clock for OLED UI
    // ==========================================
    reg [3:0] clk_divider = 4'd0;
    always @(posedge clk) clk_divider <= clk_divider + 4'd1;
    wire slow_clk = clk_divider[3];   // 100MHz / 16 = 6.25 MHz

    // ==========================================
    // 2a. SPI MIC (Pmod MIC3 on JA) feeds visuals + FSK receiver
    // ==========================================
    wire [11:0] spi_mic_data;
    wire        spi_mic_valid;

    mic_spi_interface spi_mic_inst (
        .basys3_clk (clk),
        .miso       (miso),
        .cs         (mic_cs),
        .sclk       (mic_sclk),
        .sample_data (spi_mic_data),
        .sample_valid(spi_mic_valid)
    );

    // ==========================================
    // 2b. UART MIC RX feeds NN pipeline only
    // ==========================================
    wire [11:0] uart_mic_data;
    wire        uart_mic_valid;

    uart_mic_rx uart_mic_inst (
        .basys3_clk  (clk),
        .uart_rx     (uart_rx),
        .sample_data (uart_mic_data),
        .sample_valid(uart_mic_valid)
    );

    // ==========================================
    // 3. Pre-emphasis + Hamming Window  (PIPELINE — DO NOT MODIFY)
    //    Driven by UART mic NN path only.
    // ==========================================
    wire [15:0] windowed_data;
    wire        windowed_valid;
    wire        frame_done_pulse;

    preemphasis_hamming front_end_inst (
        .basys3_clk     (clk),
        .sample_data    (uart_mic_data),
        .sample_valid   (uart_mic_valid),
        .windowed_sample(windowed_data),
        .sample_index   (),
        .frame_start    (),
        .frame_done     (frame_done_pulse),
        .out_valid      (windowed_valid)
    );

    // ==========================================
    // X-Shield (hardware safe tie-offs)
    // ==========================================
    wire [31:0] safe_fft_tdata  = windowed_valid ? {16'h0000, windowed_data} : 32'd0;
    wire        safe_fft_tlast  = windowed_valid ? frame_done_pulse : 1'b0;
    wire        safe_fft_tvalid = windowed_valid;
    wire [31:0] complex_data;
    wire        complex_valid, complex_ready, complex_last;
    wire [31:0] safe_cordic_tdata  = complex_valid ? complex_data : 32'd0;
    wire        safe_cordic_tvalid = complex_valid;

    // ==========================================
    // FFT Config Handshake (1-shot)
    // ==========================================
    reg  config_valid = 1'b1;
    wire config_ready;
    always @(posedge clk) begin
        if (!aresetn) config_valid <= 1'b1;
        else if (config_valid && config_ready) config_valid <= 1'b0;
    end

    // ==========================================
    // 4. FFT IP Core  
    // ==========================================
    fft_ip_core fft_inst (
        .aclk                 (clk),
        .aresetn              (aresetn),
        .s_axis_config_tdata  (16'h5555),
        .s_axis_config_tvalid (config_valid),
        .s_axis_config_tready (config_ready),
        .s_axis_data_tdata    (safe_fft_tdata),
        .s_axis_data_tvalid   (safe_fft_tvalid),
        .s_axis_data_tready   (),
        .s_axis_data_tlast    (safe_fft_tlast),
        .m_axis_data_tdata    (complex_data),
        .m_axis_data_tvalid   (complex_valid),
        .m_axis_data_tready   (complex_ready),
        .m_axis_data_tlast    (complex_last),
        .m_axis_status_tready (1'b1)
    );

    // ==========================================
    // 5. CORDIC 
    // ==========================================
    wire [31:0] cordic_out_data;
    wire        magnitude_valid, magnitude_last;
    wire        mfcc_mag_tready;

    cordic_ip_core mag_inst (
        .aclk                   (clk),
        .aresetn                (aresetn),
        .s_axis_cartesian_tdata (safe_cordic_tdata),
        .s_axis_cartesian_tvalid(safe_cordic_tvalid),
        .s_axis_cartesian_tready(complex_ready),
        .s_axis_cartesian_tlast (complex_last),
        .m_axis_dout_tdata      (cordic_out_data),
        .m_axis_dout_tvalid     (magnitude_valid),
        .m_axis_dout_tlast      (magnitude_last),
        .m_axis_dout_tready     (mfcc_mag_tready)
    );

    // ==========================================
    // 6. MFCC Processor  
    // ==========================================
    wire signed [31:0] mfcc_coeff_out;
    wire               mfcc_valid;
    wire               mfcc_last;
    wire signed [39:0] dct_accum_probe;

    mfcc_processor #(
        .NUM_MEL  (26),
        .NUM_CEP  (13),
        .FFT_BINS (256)
    ) mfcc_inst (
        .clk            (clk),
        .rst_n          (aresetn),
        .mag_tdata      (cordic_out_data),
        .mag_tvalid     (magnitude_valid),
        .mag_tlast      (magnitude_last),
        .mag_tready     (mfcc_mag_tready),
        .mfcc_coeff_out (mfcc_coeff_out),
        .mfcc_valid     (mfcc_valid),
        .mfcc_last      (mfcc_last),
        .dct_accum_probe(dct_accum_probe)
    );

    // ==========================================
    // 7a. UART Activity Monitor  
    // mic_valid fires at ~16kHz. 500ms silence uart_done_pulse.
    // ==========================================
    localparam UART_TIMEOUT = 50_000_000;  // 500ms at 100MHz

    reg [25:0] uart_timer      = 26'd0;
    reg        uart_active     = 1'b0;
    reg        uart_start_pulse = 1'b0;
    reg        uart_done_pulse  = 1'b0;

    always @(posedge clk) begin
        uart_start_pulse <= 1'b0;
        uart_done_pulse  <= 1'b0;
        if (!aresetn) begin
            uart_timer      <= 26'd0;
            uart_active     <= 1'b0;
        end else if (uart_mic_valid) begin
            uart_timer <= 26'd0;
            if (!uart_active) begin
                uart_active      <= 1'b1;
                uart_start_pulse <= 1'b1;
            end
        end else begin
            if (uart_active) begin
                if (uart_timer == UART_TIMEOUT - 1) begin
                    uart_active    <= 1'b0;
                    uart_done_pulse <= 1'b1;
                    uart_timer     <= 26'd0;
                end else begin
                    uart_timer <= uart_timer + 26'd1;
                end
            end
        end
    end

    // ==========================================
    // 7b. NN Input Buffer  
    // ==========================================
    wire [13311:0] mfcc_window_flat;
    wire           nn_start;
    wire           nn_buffer_full;

    nn_input_buffer nn_buf_inst (
        .clk             (clk),
        .rst_n           (aresetn),
        .reset_window    (uart_start_pulse),
        .mfcc_coeff_out  (mfcc_coeff_out),
        .mfcc_valid      (mfcc_valid),
        .mfcc_last       (mfcc_last),
        .mfcc_window_flat(mfcc_window_flat),
        .nn_start        (nn_start),
        .buffer_full_out (nn_buffer_full)
    );

    // ==========================================
    // 7c. Speaker NN
    // ==========================================
    wire        nn_valid;
    wire signed [31:0] nn_logit0, nn_logit1;

    speaker_nn nn_inst (
        .clk          (clk),
        .rst_n        (aresetn),
        .start        (nn_start),
        .mfcc_in_flat (mfcc_window_flat),
        .valid        (nn_valid),
        .logit0       (nn_logit0),
        .logit1       (nn_logit1)
    );

    // ==========================================
    // 7d. Majority Voting 
    // ==========================================
    wire [9:0]  frame_count;
    wire [9:0]  kcount, scount;   // 10-bit: supports up to 800 votes in 8s window

    // sw[5:4]: runtime SINDHU_BIAS selector — 00=0, 01=1, 10=2, 11=3
    majority_voting mv_inst (
        .clk            (clk),
        .rst            (~aresetn),
        .auto_rst       (uart_start_pulse),
        .nn_valid       (nn_valid),
        .score_kaushik  (nn_logit0),
        .score_sindhu   (nn_logit1),
        .sindhu_bias_sel(sw[5:4]),
        .kaushik_count  (kcount),
        .sindhu_count   (scount),
        .frame_count_out(frame_count)
    );

    // ==========================================
    // 7e. Final speaker latch
    // ==========================================
    reg show_final    = 1'b0;
    reg final_speaker = 1'b0;   // 0=Kaushik, 1=Sindhu

    always @(posedge clk) begin
        if (!aresetn || uart_start_pulse) begin
            show_final    <= 1'b0;
            final_speaker <= 1'b0;
        end else if (uart_done_pulse) begin
            show_final    <= 1'b1;
            final_speaker <= (scount > kcount) ? 1'b1 : 1'b0;
        end
    end

    // ==========================================
    // 8. SPI mic display pipeline
    //    Separate FFT+CORDIC chain driven by spi_mic for OLED visualizer + LEDs.
    //    Completely independent of the NN UART pipeline above.
    // ==========================================

    // Pre-emphasis for display (reuses module, separate instance)
    wire [15:0] disp_windowed_data;
    wire        disp_windowed_valid;
    wire        disp_frame_done_pulse;

    preemphasis_hamming disp_front_end_inst (
        .basys3_clk     (clk),
        .sample_data    (spi_mic_data),
        .sample_valid   (spi_mic_valid),
        .windowed_sample(disp_windowed_data),
        .sample_index   (),
        .frame_start    (),
        .frame_done     (disp_frame_done_pulse),
        .out_valid      (disp_windowed_valid)
    );

    wire [31:0] disp_safe_fft_tdata  = disp_windowed_valid ? {16'h0000, disp_windowed_data} : 32'd0;
    wire        disp_safe_fft_tvalid = disp_windowed_valid;
    wire        disp_safe_fft_tlast  = disp_windowed_valid ? disp_frame_done_pulse : 1'b0;

    reg  disp_config_valid = 1'b1;
    wire disp_config_ready;
    always @(posedge clk) begin
        if (!aresetn) disp_config_valid <= 1'b1;
        else if (disp_config_valid && disp_config_ready) disp_config_valid <= 1'b0;
    end

    wire [31:0] disp_complex_data;
    wire        disp_complex_valid, disp_complex_ready, disp_complex_last;

    fft_ip_core disp_fft_inst (
        .aclk                 (clk),
        .aresetn              (aresetn),
        .s_axis_config_tdata  (16'h5555),
        .s_axis_config_tvalid (disp_config_valid),
        .s_axis_config_tready (disp_config_ready),
        .s_axis_data_tdata    (disp_safe_fft_tdata),
        .s_axis_data_tvalid   (disp_safe_fft_tvalid),
        .s_axis_data_tready   (),
        .s_axis_data_tlast    (disp_safe_fft_tlast),
        .m_axis_data_tdata    (disp_complex_data),
        .m_axis_data_tvalid   (disp_complex_valid),
        .m_axis_data_tready   (disp_complex_ready),
        .m_axis_data_tlast    (disp_complex_last),
        .m_axis_status_tready (1'b1)
    );

    wire [31:0] disp_safe_cordic_tdata  = disp_complex_valid ? disp_complex_data : 32'd0;
    wire [31:0] disp_cordic_out_data;
    wire        disp_magnitude_valid, disp_magnitude_last;
    cordic_ip_core disp_mag_inst (
        .aclk                   (clk),
        .aresetn                (aresetn),
        .s_axis_cartesian_tdata (disp_safe_cordic_tdata),
        .s_axis_cartesian_tvalid(disp_complex_valid),
        .s_axis_cartesian_tready(disp_complex_ready),
        .s_axis_cartesian_tlast (disp_complex_last),
        .m_axis_dout_tdata      (disp_cordic_out_data),
        .m_axis_dout_tvalid     (disp_magnitude_valid),
        .m_axis_dout_tlast      (disp_magnitude_last),
        .m_axis_dout_tready     (1'b1)   
    );

    // FFT bin capture 
    wire disp_mag_transfer = disp_magnitude_valid;  // tready=1'b1, always transfers
    reg [8:0]  bin_cnt  = 9'd0;
    reg [15:0] max_mag  = 16'd0;
    reg [15:0] vu_meter = 16'd0;
    reg [5:0]  fft_bins [0:31];

    always @(posedge clk) begin
        if (!aresetn) begin
            bin_cnt  <= 9'd0;
            max_mag  <= 16'd0;
            vu_meter <= 16'd0;
        end else if (disp_mag_transfer) begin
            if (bin_cnt > 9'd5) begin
                if (disp_cordic_out_data[15:0] > max_mag) max_mag <= disp_cordic_out_data[15:0];
            end
            if (bin_cnt >= 9'd20 && bin_cnt < 9'd52) begin
                if (disp_cordic_out_data[15:9] > 63) fft_bins[bin_cnt - 20] <= 6'd63;
                else fft_bins[bin_cnt - 20] <= disp_cordic_out_data[14:9];
            end
            if (disp_magnitude_last) begin
                vu_meter[0]  <= (max_mag > 16'd800);   vu_meter[1]  <= (max_mag > 16'd1200);
                vu_meter[2]  <= (max_mag > 16'd2000);  vu_meter[3]  <= (max_mag > 16'd3000);
                vu_meter[4]  <= (max_mag > 16'd4500);  vu_meter[5]  <= (max_mag > 16'd6000);
                vu_meter[6]  <= (max_mag > 16'd8000);  vu_meter[7]  <= (max_mag > 16'd10000);
                vu_meter[8]  <= (max_mag > 16'd13000); vu_meter[9]  <= (max_mag > 16'd16000);
                vu_meter[10] <= (max_mag > 16'd19000); vu_meter[11] <= (max_mag > 16'd22000);
                vu_meter[12] <= (max_mag > 16'd25000); vu_meter[13] <= (max_mag > 16'd28000);
                vu_meter[14] <= (max_mag > 16'd31000); vu_meter[15] <= (max_mag > 16'd34000);
                max_mag <= 16'd0;
                bin_cnt <= 9'd0;
            end else begin
                bin_cnt <= bin_cnt + 9'd1;
            end
        end
    end

    reg [191:0] oled_fft_flat_reg;
    integer i;
    always @(*) begin
        for (i = 0; i < 32; i = i + 1)
            oled_fft_flat_reg[(i*6) +: 6] = fft_bins[i];
    end
    wire [191:0] oled_fft_flat = oled_fft_flat_reg;

    assign led = vu_meter;

    // ==========================================
    // 9. MFCC Display Scaler
    //    Heatmap shows NN input coefficients only active during UART analysis.
    // ==========================================
    wire [51:0] oled_mfcc_flat;

    mfcc_display_scaler ui_scaler_inst (
        .clk           (clk),
        .rst_n         (aresetn),
        .mfcc_coeff_in (mfcc_coeff_out),
        .mfcc_valid_in (mfcc_valid),
        .mfcc_last_in  (mfcc_last),
        .oled_mfcc_flat(oled_mfcc_flat)
    );

    // ==========================================
    // 10. FSK Transmitter
    // ==========================================
    wire [39:0] fsk_tx_data;
    wire        fsk_tx_trigger;
    wire [11:0] dac_data;
    wire        dac_valid;

    FSK_T transmitter (
        .SW         (fsk_tx_data),
        .BTNC       (fsk_tx_trigger),
        .basys3_clk (clk),
        .dac_data   (dac_data),
        .dac_valid  (dac_valid)
    );

    da2_spi dac_driver (
        .clk     (clk),
        .rst     (reset_btn),
        .dac_data(dac_data),
        .dac_valid(dac_valid),
        .sync_n  (dac_sync_n),
        .din     (dac_mosi),
        .sclk    (dac_sclk_out)
    );

    // ==========================================
    // 11. FSK Receiver
    // ==========================================
    wire [39:0] fsk_rx_data;
    wire        fsk_rx_valid_raw;

    fsk_receiver receiver (
        .clk         (clk),
        .rst         (reset_btn),
        .sample      (spi_mic_data),
        .sample_rdy  (spi_mic_valid),
        .sensitivity (sw[14:13]),
        .decoded_data(fsk_rx_data),
        .data_valid  (fsk_rx_valid_raw),
        .rx_msg_counter()
    );


    // Stretch rx_valid for 2-stage CDC into slow_clk domain
    reg [7:0] rx_stretch = 8'd0;
    always @(posedge clk) begin
        if (fsk_rx_valid_raw) rx_stretch <= 8'd255;
        else if (rx_stretch > 0) rx_stretch <= rx_stretch - 8'd1;
    end
    wire ui_rx_valid = (rx_stretch > 0);

    // ==========================================
    // 12. OLED Top-Level UI
    // ==========================================

    // (32 cycles � 10ns = 320ns, comfortably > one 160ns slow_clk period).
    // Then edge-detect on the slow_clk side to produce a clean 1-cycle pulse.
    reg [4:0] uart_start_stretch = 5'd0;
    reg [4:0] uart_done_stretch  = 5'd0;
    always @(posedge clk) begin
        if (uart_start_pulse)      uart_start_stretch <= 5'd31;
        else if (uart_start_stretch > 0) uart_start_stretch <= uart_start_stretch - 5'd1;

        if (uart_done_pulse)       uart_done_stretch  <= 5'd31;
        else if (uart_done_stretch  > 0) uart_done_stretch  <= uart_done_stretch  - 5'd1;
    end
    wire uart_start_level = (uart_start_stretch > 0);
    wire uart_done_level  = (uart_done_stretch  > 0);

    // 2-stage sync into slow_clk, then edge-detect for single-cycle pulse
    reg uart_start_s1 = 1'b0, uart_start_s2 = 1'b0, uart_start_s3 = 1'b0;
    reg uart_done_s1  = 1'b0, uart_done_s2  = 1'b0, uart_done_s3  = 1'b0;
    always @(posedge slow_clk) begin
        uart_start_s1 <= uart_start_level;
        uart_start_s2 <= uart_start_s1;
        uart_start_s3 <= uart_start_s2;
        uart_done_s1  <= uart_done_level;
        uart_done_s2  <= uart_done_s1;
        uart_done_s3  <= uart_done_s2;
    end
    wire uart_start_sync = uart_start_s2 & ~uart_start_s3;  // rising edge 1-cycle pulse
    wire uart_done_sync  = uart_done_s2  & ~uart_done_s3;

    top_level_ui oled_ui (
        .clk             (slow_clk),
        .reset           (reset_btn),

        // Buttons & switches
        .sw0             (sw[0]),
        .sw1             (sw[1]),
        .sw3             (sw[3]),
        .btnU            (btnU),
        .btnD            (btnD),
        .btnC            (btnC),
        .btnL            (btnL),
        .btnR            (btnR),

        // UART activity triggers properly stretched + edge-detected into slow_clk
        .uart_start      (uart_start_sync),
        .uart_done       (uart_done_sync),

        // NN result counts for pie chart
        .kaushik_count   (kcount),
        .sindhu_count    (scount),

        // FSK wires
        .tx_data         (fsk_tx_data),
        .tx_trigger      (fsk_tx_trigger),
        .rx_data         (fsk_rx_data),
        .rx_valid        (ui_rx_valid),

        // OLED visualizer feeds
        .fft_data_flat   (oled_fft_flat),
        .mfcc_data_flat  (oled_mfcc_flat),

        // OLED physical
        .cs              (oled_cs),
        .sdin            (oled_sdin),
        .sclk            (oled_sclk),
        .d_cn            (oled_d_cn),
        .resn            (oled_resn),
        .vccen           (oled_vccen),
        .pmoden          (oled_pmoden)
    );

endmodule
