`timescale 1ns / 1ps
module tt_um_wallace_multiplier_serial (
    input wire       clk,
    input wire       rst_n,
    input wire       ena,
    input wire [7:0] ui_in,
    input wire [7:0] uio_in, 
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    output reg [7:0] uo_out 
);
    localparam [1:0] READ = 2'd0, COMPUTE = 2'd1, WRITE = 2'd2;
    reg [1:0] state;
    reg [2:0] byte_count;
    reg [47:0] input_reg, output_reg;
    wire [47:0] product;

    wallace_multiplier multiplier (
        .a(input_reg [23:0]),
        .b(input_reg [47:24]),
        .c(product));    

    assign uio_out = 0;
    assign uio_oe  = 0;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= READ;
            byte_count <= 3'd0;
            input_reg  <= 48'd0;
            output_reg <= 48'd0;
            uo_out   <= 8'd0;
        end else if (ena) begin
            case (state)
                READ: begin
                    input_reg <= {input_reg[39:0], ui_in};
                    if (byte_count == 3'd5) begin
                        byte_count <= 3'd0;
                        state <= COMPUTE;
                    end else
                        byte_count <= byte_count + 3'd1;
                end
                COMPUTE: begin
                    output_reg <= product;
                    byte_count <= 3'd0;
                    state <= WRITE;
                end
                WRITE: begin
                    uo_out <= output_reg[47:40];
                    output_reg <= {output_reg[39:0], 8'd0};
                    if (byte_count == 3'd5) begin
                        byte_count <= 3'd0;
                        state <= READ;
                    end else
                        byte_count <= byte_count + 3'd1;
                end
                default: begin
                    state <= READ;
                    byte_count <= 3'd0;
                end
            endcase
        end
    end
endmodule
