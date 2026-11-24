`timescale 1ns/1ps
module tb_wallace_multiplier_serial;
    reg clk, rst, cs;
    reg [7:0] data_in;
    wire [7:0] data_out;
    integer seed, initial_seed, num_tests, i, passed;
    reg [23:0] a, b;

    wallace_multiplier_serial dut (
        .clk(clk), .rst(rst), .cs(cs),
        .data_in(data_in), .data_out(data_out)
    );
    always #10 clk = ~clk;

    // Drive on falling edge; sample after rising-edge NBA updates.
    task tick;
        input enable;
        input [7:0] byte_in;
        begin
            @(negedge clk);
            cs = enable;
            data_in = byte_in;
            @(posedge clk);
            #1;
        end
    endtask

    task pause_cycle;
        reg [7:0] held;
        begin
            held = data_out;
            tick(1'b0, 8'hA5);
            if (data_out !== held) begin
                $display("ASSERT FAIL: output changed while cs=0 at %0t", $time);
                $finish;
            end
        end
    endtask

    task check_product;
        input [23:0] operand_a, operand_b;
        input stalls;
        reg [47:0] expected, received, payload;
        reg [7:0] held;
        integer j;
        begin
            expected = {24'b0, operand_a} * {24'b0, operand_b};
            payload = {operand_a, operand_b};
            received = 48'b0;
            held = data_out;
            for (j=5; j>=0; j=j-1) begin
                if (stalls && j==3) pause_cycle;
                tick(1'b1, payload[j*8 +: 8]);
                if (data_out !== held) begin
                    $display("ASSERT FAIL: output changed during READ");
                    $finish;
                end
            end
            if (stalls) pause_cycle;
            tick(1'b1, 8'h00); // COMPUTE
            if (data_out !== held) begin
                $display("ASSERT FAIL: output changed during COMPUTE");
                $finish;
            end
            for (j=5; j>=0; j=j-1) begin
                if (stalls && j==2) pause_cycle;
                tick(1'b1, 8'h00);
                received = {received[39:0], data_out};
                if (data_out !== expected[j*8 +: 8]) begin
                    $display("ASSERT FAIL: seed=%0d test=%0d A=%h B=%h byte=%0d expected=%h actual=%h", initial_seed, passed, operand_a, operand_b, j, expected[j*8 +: 8], data_out);
                    $finish;
                end
            end
            if (received !== expected) begin
                $display("ASSERT FAIL: A=%h B=%h expected=%h actual=%h", operand_a, operand_b, expected, received);
                $finish;
            end
            passed = passed + 1;
        end
    endtask

    initial begin
        clk=0; rst=1; cs=0; data_in=0; passed=0;
        seed=12345; num_tests=1000;
        if ($value$plusargs("SEED=%d", seed)) begin end
        if ($value$plusargs("N=%d", num_tests)) begin end
        initial_seed=seed;
        $display("Starting test: seed=%0d random cases=%0d", seed, num_tests);
        repeat (2) @(posedge clk);
        #1;
        if (data_out !== 8'h00) begin
            $display("ASSERT FAIL: reset output"); $finish;
        end
        @(negedge clk); rst=0;
        check_product(24'h0, 24'hFFFFFF, 0);
        check_product(24'h1, 24'hFFFFFF, 0);
        check_product(24'hFFFFFF, 24'hFFFFFF, 1);
        check_product(24'h800000, 24'h800000, 0);
        check_product(24'hAAAAAA, 24'h555555, 1);
        for (i=0; i<num_tests; i=i+1) begin
            a=$random(seed);
            b=$random(seed);
            check_product(a,b,(i%10)==0);
        end
        $display("PASS: %0d transactions, seed=%0d", passed, initial_seed);
        $finish;
    end
endmodule
