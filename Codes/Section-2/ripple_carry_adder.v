
 // One-bit full adder
module full_adder (
    input  wire a,
    input  wire b,
    input  wire cin,
    output wire sum,
    output wire cout
);
    assign sum  = a ^ b ^ cin;
    assign cout = (a & b) | (a & cin) | (b & cin);
endmodule

// N-bit ripple carry adder; N must be at least 1.
module ripple_carry_adder #(
    parameter N = 4
)(
    input  wire [N-1:0] a,
    input  wire [N-1:0] b,
    input  wire         cin,
    output wire [N-1:0] sum,
    output wire         cout
);
    wire [N:0] carry;

    assign carry[0] = cin;
    assign cout     = carry[N];

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : gen_full_adders
            full_adder fa (
                .a    (a[i]),
                .b    (b[i]),
                .cin  (carry[i]),
                .sum  (sum[i]),
                .cout (carry[i+1])
            );
        end
    endgenerate
endmodule
