`timescale 1ns / 1ps

// Person in charge - Kaushik Saravanan

module da2_spi (
    input         clk,
    input         rst,
    input  [11:0] dac_data,
    input         dac_valid,
    output reg    sync_n = 1'b1,
    output reg    din    = 1'b0,
    output reg    sclk   = 1'b1
);

    localparam HALF = 4;

    reg        busy      = 0;
    reg [15:0] shift_reg = 0;
    reg [4:0]  bit_cnt   = 0;
    reg [2:0]  clk_cnt   = 0;

    always @(posedge clk) begin
        if (rst) begin
            sync_n <= 1'b1;
            sclk   <= 1'b1;
            din    <= 1'b0;
            busy   <= 1'b0;
        end else if (dac_valid && !busy) begin
            shift_reg <= {4'b0000, dac_data};
            sync_n    <= 1'b0;
            busy      <= 1'b1;
            bit_cnt   <= 0;
            clk_cnt   <= 0;
        end else if (busy) begin
            clk_cnt <= clk_cnt + 1;

            // Falling edge: present data, DA2 latches
            if (clk_cnt == HALF - 1 && sclk == 1'b1) begin
                sclk    <= 1'b0;
                din     <= shift_reg[15];
                clk_cnt <= 0;
            end

            // Rising edge: shift to next bit
            if (clk_cnt == HALF - 1 && sclk == 1'b0) begin
                sclk      <= 1'b1;
                shift_reg <= {shift_reg[14:0], 1'b0};
                bit_cnt   <= bit_cnt + 1;
                clk_cnt   <= 0;

                if (bit_cnt == 15) begin
                    sync_n <= 1'b1;
                    busy   <= 1'b0;
                end
            end
        end
    end

endmodule