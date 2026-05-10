`timescale 1ns / 1ps

// Person in charge - Kaushik Saravanan
// Module for PMOD MIC3 producing valid 12-bit audio samples @ 16 kHz
// sample_valid handshake signals downstream buffer module of data validity

module mic_spi_interface(
    input  wire             basys3_clk, 
    input  wire             miso,
    output reg              cs   = 1'b1,
    output reg              sclk = 1'b1,
    output reg[11:0] sample_data = 12'd0,
    output reg      sample_valid = 1'b0     
    );
    
    localparam SCLK_HALF    = 50;       
    localparam SAMPLE_TICKS = 6250;
    
    localparam S_IDLE  = 2'd0;
    localparam S_SHIFT = 2'd1;
    localparam S_DONE  = 2'd2;
    
    reg [1:0]  state        = S_IDLE;
    reg [12:0] sample_timer = 13'd0;
    reg [6:0]  clk_div      = 7'd0;
    reg [4:0]  bit_cnt      = 5'd0;
    reg [11:0] shift_reg    = 12'd0;
    
    always @(posedge basys3_clk) begin
        sample_valid <= 1'b0;
    
        if (sample_timer == SAMPLE_TICKS - 1)
            sample_timer <= 13'd0;
        else
            sample_timer <= sample_timer + 1;
    
        case (state)
    
            S_IDLE: begin
                cs      <= 1'b1;
                sclk    <= 1'b1;
                clk_div <= 6'd0;
                bit_cnt <= 5'd0;
    
                if (sample_timer == 0) begin
                    cs    <= 1'b0;
                    state <= S_SHIFT;
                end
            end
    
            S_SHIFT: begin
                clk_div <= clk_div + 1;
    
                if (clk_div == SCLK_HALF - 1)
                    sclk <= 1'b0;
    
                if (clk_div == 2*SCLK_HALF - 1) begin
                    sclk      <= 1'b1;
                    shift_reg <= {shift_reg[10:0], miso};
                    clk_div   <= 6'd0;
                    
                    bit_cnt <= bit_cnt + 1;
    
                    if (bit_cnt == 5'd15)
                        state <= S_DONE;
                        
                end
            end
    
            S_DONE: begin
                cs           <= 1'b1;
                sclk         <= 1'b1;
                sample_data  <= shift_reg;
                sample_valid <= 1'b1;
                state        <= S_IDLE;
            end
    
        endcase
    end
                         
    
endmodule
