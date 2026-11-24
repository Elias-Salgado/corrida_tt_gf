`default_nettype none

module weight_storage (
    input wire clk, input wire rst_n, input wire s_data,
    input wire s_clk_en, input wire mode_prog,
    output reg [127:0] weights, output wire prog_done
);
    reg [7:0] bit_cnt;
    assign prog_done = (bit_cnt == 8'd128);

    always @(posedge clk) begin
        if (!rst_n) begin
            weights <= 128'b0;
            bit_cnt <= 8'b0;
        end else if (mode_prog && s_clk_en) begin
            weights <= {weights[126:0], s_data};
            if (bit_cnt < 128) bit_cnt <= bit_cnt + 1;
        end
    end
endmodule