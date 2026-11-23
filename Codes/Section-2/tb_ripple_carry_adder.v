
`timescale 1ns/1ps

module tb_ripple_carry_adder;
    localparam N = 4;
    localparam TOTAL_CASES = 1 << (2*N + 1);

    reg [N-1:0] a, b;
    reg cin;
    wire [N-1:0] sum;
    wire cout;
    reg [N:0] expected;
    integer i;
    integer passed, failed;

    ripple_carry_adder #(.N(N)) dut (
        .a(a), .b(b), .cin(cin),
        .sum(sum), .cout(cout)
    );

    initial begin
        passed = 0;
        failed = 0;

        // Exhaustively check a, b and cin: 512 cases for N=4.
        for (i = 0; i < TOTAL_CASES; i = i + 1) begin
            {a, b, cin} = i;
            expected = {1'b0, a} + {1'b0, b} + cin;
            #10;

            if ({cout, sum} !== expected) begin
                failed = failed + 1;
                $display("FAIL: a=%h b=%h cin=%b expected=%h actual=%h",
                         a, b, cin, expected, {cout, sum});
            end else begin
                passed = passed + 1;
            end
        end

        $display("Ripple carry adder: passed=%0d failed=%0d tested=%0d/%0d",
                 passed, failed, passed + failed, TOTAL_CASES);
        if (failed == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end
endmodule
