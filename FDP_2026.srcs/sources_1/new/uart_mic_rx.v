`timescale 1ns / 1ps

module uart_mic_rx (
    input  wire        basys3_clk,
    input  wire        uart_rx,
    output reg  [11:0] sample_data  = 12'd0,
    output reg         sample_valid = 1'b0
);
    localparam BAUD_DIV  = 100;
    localparam HALF_BAUD = 50;

    localparam U_IDLE  = 2'd0;
    localparam U_START = 2'd1;
    localparam U_DATA  = 2'd2;
    localparam U_STOP  = 2'd3;

    reg [1:0] u_state   = U_IDLE;
    reg [6:0] baud_cnt  = 7'd0;
    reg [2:0] bit_cnt   = 3'd0;
    reg [7:0] shift_reg = 8'd0;
    reg       byte_valid = 1'b0;
    reg [7:0] byte_out   = 8'd0;

    reg rx_d0 = 1'b1, rx_d1 = 1'b1;
    always @(posedge basys3_clk) begin
        rx_d0 <= uart_rx;
        rx_d1 <= rx_d0;
    end

    always @(posedge basys3_clk) begin
        byte_valid <= 1'b0;
        case (u_state)
            U_IDLE:  if (!rx_d1) begin baud_cnt <= 7'd0; u_state <= U_START; end
            U_START: if (baud_cnt == HALF_BAUD - 1) begin
                         baud_cnt <= 7'd0; bit_cnt <= 3'd0; u_state <= U_DATA;
                     end else baud_cnt <= baud_cnt + 1;
            U_DATA:  if (baud_cnt == BAUD_DIV - 1) begin
                         baud_cnt  <= 7'd0;
                         shift_reg <= {rx_d1, shift_reg[7:1]};
                         if (bit_cnt == 3'd7) u_state <= U_STOP;
                         else bit_cnt <= bit_cnt + 1;
                     end else baud_cnt <= baud_cnt + 1;
            U_STOP:  if (baud_cnt == BAUD_DIV - 1) begin
                         baud_cnt <= 7'd0; byte_out <= shift_reg;
                         byte_valid <= 1'b1; u_state <= U_IDLE;
                     end else baud_cnt <= baud_cnt + 1;
        endcase
    end

    reg        got_msb    = 1'b0;
    reg [3:0]  msb_nibble = 4'd0;

    always @(posedge basys3_clk) begin
        sample_valid <= 1'b0;
        if (byte_valid) begin
            if (!got_msb) begin
                msb_nibble <= byte_out[3:0];
                got_msb    <= 1'b1;
            end else begin
                sample_data  <= {msb_nibble, byte_out};
                sample_valid <= 1'b1;
                got_msb      <= 1'b0;
            end
        end
    end
endmodule