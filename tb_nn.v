`timescale 1ns / 1ps

module tb_nn;

    reg [31:0] input_1;
    reg [31:0] input_2;
    reg clk;
    reg resetn;
    reg enable;

    wire [31:0] final_output;
    wire total_ovf;
    wire total_zero;
    wire [2:0] ovf_fsm_stage;
    wire [2:0] zero_fsm_stage;

    integer tests_run;
    integer tests_passed;
    integer tests_failed;

    nn dut (
        .input_1(input_1),
        .input_2(input_2),
        .clk(clk),
        .resetn(resetn),
        .enable(enable),
        .final_output(final_output),
        .total_ovf(total_ovf),
        .total_zero(total_zero),
        .ovf_fsm_stage(ovf_fsm_stage),
        .zero_fsm_stage(zero_fsm_stage)
    );

    always #5 clk = ~clk; 

    `include "nn_model.v"

    integer i;
    reg [31:0] expected_out;
    reg [31:0] rand_val1, rand_val2;
    
    localparam MAX_POS = 32'h7FFFFFFF;
    localparam MAX_NEG = 32'h80000000;

    initial begin
        clk = 0;
        resetn = 0;
        enable = 0;
        input_1 = 0;
        input_2 = 0;
        tests_run = 0;
        tests_passed = 0;
        tests_failed = 0;

        #20 resetn = 1;
        #20 enable = 1; 

        $display("--- Starting ROM Load ---");
        #300; 

        $display("--- Starting Test Loop ---");

        for (i = 0; i < 100; i = i + 1) begin
            rand_val1 = $signed($urandom_range(0, 8191)) - 4096;
            rand_val2 = $signed($urandom_range(0, 8191)) - 4096;
            run_test_case(rand_val1, rand_val2);
            
            rand_val1 = $signed(MAX_POS) - $urandom_range(0, MAX_POS/2);
            rand_val2 = $signed(MAX_POS) - $urandom_range(0, MAX_POS/2);
            run_test_case(rand_val1, rand_val2);

            rand_val1 = $signed(MAX_NEG) + $urandom_range(0, (MAX_POS/2)); 
            rand_val2 = $signed(MAX_NEG) + $urandom_range(0, (MAX_POS/2));
            run_test_case(rand_val1, rand_val2);
        end

        $display("--- Tests Completed ---");
        $display("Total: %0d | Passed: %0d | Failed: %0d", tests_run, tests_passed, tests_failed);
        $stop;
    end


    task run_test_case;
        input [31:0] in1;
        input [31:0] in2;
        begin
            tests_run = tests_run + 1;
            
            input_1 = in1;
            input_2 = in2;
            
            enable = 0;
            wait (dut.current_state == 3'b110);
            @(posedge clk); 
            
            enable = 1; 
            #20; 
            enable = 0; 

            #150; 

            expected_out = nn_model($signed(input_1), $signed(input_2));
            
            if (total_ovf) begin
                 expected_out = 32'hFFFFFFFF;
            end
            
            if (final_output !== expected_out) begin
                $display("FAIL [Time: %0t] Iter: %0d | Inputs: %d, %d | Expected: %h | Got: %h (OVF: %b)", 
                         $time, i, $signed(input_1), $signed(input_2), expected_out, final_output, total_ovf);
                tests_failed = tests_failed + 1;
            end else begin
                tests_passed = tests_passed + 1;
            end
            
            #10;
        end
    endtask

endmodule
