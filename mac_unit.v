module mac_unit(
    input wire [31:0] op1,
    input wire [31:0] op2,
    input wire [31:0] op3,
    output wire [31:0] total_result,
    output wire zero_mul,
    output wire zero_add,
    output wire ovf_mul,
    output wire ovf_add
);

    wire [31:0] mult_result;
    
    alu alu_mul (
        .op1(op1),
        .op2(op2),
        .alu_op(4'b0110), 
        .zero(zero_mul),
        .result(mult_result),
        .ovf(ovf_mul)
    );

    alu alu_add (
        .op1(mult_result),
        .op2(op3),
        .alu_op(4'b0100), 
        .zero(zero_add),
        .result(total_result),
        .ovf(ovf_add)
    );

endmodule
