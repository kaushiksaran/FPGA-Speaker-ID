`timescale 1ns / 1ps

module preemphasis_hamming(
    input  wire        basys3_clk,      
    input  wire [11:0] sample_data,     
    input  wire        sample_valid,    
    output reg  [15:0] windowed_sample, 
    output reg  [8:0]  sample_index,    
    output reg         frame_start,     
    output reg         frame_done,      
    output wire        out_valid        
);

// 1. DC removal
wire signed [15:0] x_dc = $signed({1'b0, sample_data}) - 16'sd2048;

// 2. Pre-emphasis filter
reg signed [15:0] x_prev = 16'sd0;
wire signed [23:0] coeff_term  = $signed(x_prev) * $signed(8'sd124); 
wire signed [15:0] alpha_xprev = coeff_term[22:7]; 
wire signed [15:0] preemph_out = x_dc - alpha_xprev;

always @(posedge basys3_clk) begin
    if (sample_valid) x_prev <= x_dc;
end

// 3. Circular buffer
(* ram_style = "block" *) reg [15:0] circ_buf [0:399]; 
reg [15:0] bram_rdata = 16'd0;
reg [8:0] wr_ptr = 9'd0;
reg [8:0] fill_cnt = 9'd0;
reg buffer_filled = 1'b0;

always @(posedge basys3_clk) begin
    if (sample_valid) circ_buf[wr_ptr] <= preemph_out;
    bram_rdata <= circ_buf[sample_valid ? wr_ptr : rd_addr];
end

always @(posedge basys3_clk) begin
    if (sample_valid) begin
        wr_ptr <= (wr_ptr == 9'd399) ? 9'd0 : wr_ptr + 9'd1;
        if (!buffer_filled) begin
            if (fill_cnt == 9'd399) buffer_filled <= 1'b1;
            else fill_cnt <= fill_cnt + 9'd1;
        end
    end
end

// 4. Hop counter
reg [7:0] hop_cnt = 8'd0;
reg hop_trigger = 1'b0;
always @(posedge basys3_clk) begin
    hop_trigger <= 1'b0;
    if (sample_valid && buffer_filled) begin
        if (hop_cnt == 8'd159) begin
            hop_cnt <= 8'd0;
            hop_trigger <= 1'b1;
        end else hop_cnt <= hop_cnt + 8'd1;
    end
end

// 5. Hamming window LUT
(* rom_style = "distributed" *) reg [15:0] hamming_lut [0:399];
// CRITICAL FIX: Match the exact path from your Windows machine
initial $readmemh("C:/Users/HP/Desktop/hamming_coeff.hex", hamming_lut);

// 6. Hamming multiply
wire signed [31:0] hamm_prod = $signed(bram_rdata) * $signed({1'b0, hamming_lut[rd_cnt]});
wire signed [15:0] windowed_w = hamm_prod[30:15];

// 7. Readout FSM
localparam FSM_IDLE = 3'd0, FSM_PREFETCH = 3'd1, FSM_READING = 3'd2, FSM_PADDING = 3'd3, FSM_DONE = 3'd4;
reg [2:0] rd_state = FSM_IDLE;
reg [8:0] rd_cnt = 9'd0, rd_addr = 9'd0, rd_base = 9'd0;
reg stall_r = 1'b0;

always @(posedge basys3_clk) begin
    frame_start <= 1'b0; frame_done <= 1'b0; stall_r <= 1'b0;
    case (rd_state)
        FSM_IDLE: if (hop_trigger) begin rd_base <= wr_ptr; rd_addr <= wr_ptr; rd_state <= FSM_PREFETCH; end
        FSM_PREFETCH: if (!sample_valid) begin rd_addr <= (rd_base == 399) ? 0 : rd_base + 1; rd_state <= FSM_READING; end
        FSM_READING: begin
            windowed_sample <= windowed_w; sample_index <= rd_cnt; frame_start <= (rd_cnt == 0);
            if (!stall_r && !sample_valid) rd_addr <= (rd_addr == 399) ? 0 : rd_addr + 1;
            if (sample_valid) stall_r <= 1'b1;
            if (rd_cnt == 399) begin rd_state <= FSM_PADDING; rd_cnt <= 0; end else rd_cnt <= rd_cnt + 1;
        end
        FSM_PADDING: begin
            windowed_sample <= 16'sd0; sample_index <= 9'd400 + rd_cnt;
            if (rd_cnt == 111) rd_state <= FSM_DONE; else rd_cnt <= rd_cnt + 1;
        end
        FSM_DONE: begin frame_done <= 1'b1; rd_state <= FSM_IDLE; end
    endcase
end

assign out_valid = (rd_state == FSM_READING) || (rd_state == FSM_PADDING);
endmodule