module nn(
    input wire [31:0] input_1,
    input wire [31:0] input_2,
    input wire clk,
    input wire resetn, 
    input wire enable,
    output reg [31:0] final_output,
    output reg total_ovf,
    output reg total_zero,
    output reg [2:0] ovf_fsm_stage,
    output reg [2:0] zero_fsm_stage
);

    parameter [2:0] STATE_DEACTIVATED  = 3'b000;
    parameter [2:0] STATE_LOAD         = 3'b001;
    parameter [2:0] STATE_PRE_PROC     = 3'b010;
    parameter [2:0] STATE_INPUT_LAYER  = 3'b011;
    parameter [2:0] STATE_OUTPUT_LAYER = 3'b100;
    parameter [2:0] STATE_POST_PROC    = 3'b101;
    parameter [2:0] STATE_IDLE         = 3'b110;

    reg [2:0] current_state, next_state;

    reg [4:0] load_addr_counter;
    reg loaded_flag;
    
    wire [31:0] rom_dout1, rom_dout2;
    wire [7:0] rom_addr1, rom_addr2; 

    reg [3:0] rf_raddr1, rf_raddr2, rf_raddr3, rf_raddr4;
    wire [31:0] rf_rdata1, rf_rdata2, rf_rdata3, rf_rdata4;
    reg [3:0] rf_waddr1;
    reg [3:0] rf_waddr2; 
    reg [31:0] rf_wdata1, rf_wdata2;
    reg rf_write;

    reg signed [31:0] inter1, inter2, inter3, inter4, inter5;
    
    reg internal_ovf;

    reg signed [31:0] alu1_op1, alu1_op2;
    reg [3:0] alu1_cmd;
    wire [31:0] alu1_res;
    wire alu1_zero, alu1_ovf;

    reg signed [31:0] alu2_op1, alu2_op2;
    reg [3:0] alu2_cmd;
    wire [31:0] alu2_res;
    wire alu2_zero, alu2_ovf;

    reg signed [31:0] mac1_op1, mac1_op2, mac1_op3;
    wire [31:0] mac1_res;
    wire mac1_zmul, mac1_zadd, mac1_ovf_mul, mac1_ovf_add;

    reg signed [31:0] mac2_op1, mac2_op2, mac2_op3;
    wire [31:0] mac2_res;
    wire mac2_zmul, mac2_zadd, mac2_ovf_mul, mac2_ovf_add;
    
    localparam MAX_POS = 32'h7FFFFFFF;

    WEIGHT_BIAS_MEMORY rom_inst (
        .clk(clk),
        .addr1(rom_addr1),
        .addr2(rom_addr2),
        .dout1(rom_dout1),
        .dout2(rom_dout2)
    );

    regfile rf_inst (
        .clk(clk),
        .resetn(resetn),
        .readReg1(rf_raddr1), .readData1(rf_rdata1),
        .readReg2(rf_raddr2), .readData2(rf_rdata2),
        .readReg3(rf_raddr3), .readData3(rf_rdata3),
        .readReg4(rf_raddr4), .readData4(rf_rdata4),
        .writeReg1(rf_waddr1), .writeData1(rf_wdata1),
        .writeReg2(rf_waddr2), .writeData2(rf_wdata2),
        .write(rf_write)
    );

    alu alu_inst1 (
        .op1(alu1_op1), .op2(alu1_op2), .alu_op(alu1_cmd),
        .zero(alu1_zero), .result(alu1_res), .ovf(alu1_ovf)
    );

    alu alu_inst2 (
        .op1(alu2_op1), .op2(alu2_op2), .alu_op(alu2_cmd),
        .zero(alu2_zero), .result(alu2_res), .ovf(alu2_ovf)
    );

    mac_unit mac_inst1 (
        .op1(mac1_op1), .op2(mac1_op2), .op3(mac1_op3),
        .total_result(mac1_res),
        .zero_mul(mac1_zmul), .zero_add(mac1_zadd),
        .ovf_mul(mac1_ovf_mul), .ovf_add(mac1_ovf_add)
    );


    wire [31:0] mac2_op3_final;
    assign mac2_op3_final = (current_state == STATE_OUTPUT_LAYER) ? mac1_res : mac2_op3;

    mac_unit mac_inst2 (
        .op1(mac2_op1), .op2(mac2_op2), .op3(mac2_op3_final), 
        .total_result(mac2_res),
        .zero_mul(mac2_zmul), .zero_add(mac2_zadd),
        .ovf_mul(mac2_ovf_mul), .ovf_add(mac2_ovf_add)
    );

    assign rom_addr1 = (load_addr_counter - 5'd2) * 4;
    
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            current_state <= STATE_DEACTIVATED;
            load_addr_counter <= 5'd2;
            loaded_flag <= 0;
            
            final_output <= 0;
            total_ovf <= 0;
            total_zero <= 0;
            ovf_fsm_stage <= 3'b111;
            zero_fsm_stage <= 3'b111;
            
            inter1 <= 0; inter2 <= 0; inter3 <= 0; inter4 <= 0; inter5 <= 0;
            internal_ovf <= 0;
            
        end else begin
            current_state <= next_state;

            if (current_state == STATE_LOAD) begin
                if (load_addr_counter <= 13) 
                    load_addr_counter <= load_addr_counter + 1;
                else
                    loaded_flag <= 1;
            end 

            if (current_state == STATE_PRE_PROC) begin
                 if (!internal_ovf) begin
                    inter1 <= alu1_res;
                    inter2 <= alu2_res;
                 end
            end
            
            if (current_state == STATE_INPUT_LAYER) begin
                 if (!internal_ovf) begin
                    inter3 <= mac1_res;
                    inter4 <= mac2_res;
                 end
            end
            
            if (current_state == STATE_OUTPUT_LAYER) begin
                 if (!internal_ovf) begin
                    inter5 <= mac2_res; 
                 end
            end

            if (current_state == STATE_POST_PROC) begin
                 if (!internal_ovf) begin
                    final_output <= alu1_res;
                 end
            end
            
            if (current_state == STATE_IDLE && enable) begin
                 total_ovf <= 0;
                 total_zero <= 0;
                 ovf_fsm_stage <= 3'b111;
                 zero_fsm_stage <= 3'b111;
                 internal_ovf <= 0;
            end

            if (current_state != STATE_IDLE && current_state != STATE_DEACTIVATED && current_state != STATE_LOAD) begin
                if (internal_ovf) begin
                    total_ovf <= 1;
                    final_output <= -1;
                end 
            end
            
            case (current_state)
                STATE_PRE_PROC: begin
                    if (!internal_ovf) begin
                        if (alu1_ovf || alu2_ovf) begin
                            internal_ovf <= 1;
                            ovf_fsm_stage <= STATE_PRE_PROC;
                        end
                    end
                    if (alu1_zero || alu2_zero) begin
                        total_zero <= 1;
                        if (zero_fsm_stage == 3'b111) zero_fsm_stage <= STATE_PRE_PROC;
                    end
                end
                STATE_INPUT_LAYER: begin
                    if (!internal_ovf) begin
                        if (mac1_ovf_mul || mac1_ovf_add || mac2_ovf_mul || mac2_ovf_add) begin
                            internal_ovf <= 1;
                            ovf_fsm_stage <= STATE_INPUT_LAYER;
                        end
                    end
                    if (mac1_zmul || mac1_zadd || mac2_zmul || mac2_zadd) begin
                         total_zero <= 1;
                         if (zero_fsm_stage == 3'b111) zero_fsm_stage <= STATE_INPUT_LAYER;
                    end
                end
                STATE_OUTPUT_LAYER: begin
                    if (!internal_ovf) begin
                        if (mac1_ovf_mul || mac1_ovf_add || mac2_ovf_mul || mac2_ovf_add) begin
                            internal_ovf <= 1;
                            ovf_fsm_stage <= STATE_OUTPUT_LAYER;
                        end
                    end
                    if (mac1_zmul || mac1_zadd || mac2_zmul || mac2_zadd) begin
                         total_zero <= 1;
                         if (zero_fsm_stage == 3'b111) zero_fsm_stage <= STATE_OUTPUT_LAYER;
                    end
                end
                STATE_POST_PROC: begin
                    if (!internal_ovf) begin
                         if (alu1_ovf) begin
                            internal_ovf <= 1;
                            ovf_fsm_stage <= STATE_POST_PROC;
                         end
                    end
                    if (alu1_zero) begin
                         total_zero <= 1;
                         if (zero_fsm_stage == 3'b111) zero_fsm_stage <= STATE_POST_PROC;
                    end
                end
            endcase
            
        end 
    end

    assign rom_addr2 = 0; 
    
    always @(*) begin
        next_state = current_state;
        
        rf_write = 0;
        rf_waddr1 = 0; rf_wdata1 = 0;
        rf_waddr2 = 0; rf_wdata2 = 0;
        rf_raddr1 = 0; rf_raddr2 = 0; rf_raddr3 = 0; rf_raddr4 = 0;

        alu1_op1 = 0; alu1_op2 = 0; alu1_cmd = 0;
        alu2_op1 = 0; alu2_op2 = 0; alu2_cmd = 0;
        
        mac1_op1 = 0; mac1_op2 = 0; mac1_op3 = 0;
        mac2_op1 = 0; mac2_op2 = 0; mac2_op3 = 0;

        if (internal_ovf) begin
             next_state = STATE_IDLE; 
        end else begin
            case (current_state)
                STATE_DEACTIVATED: begin
                    if (enable) begin
                        next_state = STATE_LOAD;
                    end
                end
                STATE_LOAD: begin
                     if (load_addr_counter >= 5) begin
                        rf_write = 1;
                        
                        if (load_addr_counter == 13) rf_waddr1 = 4'h0;      
                        else if (load_addr_counter == 14) rf_waddr1 = 4'h1; 
                        else begin
                             rf_waddr1 = load_addr_counter - 5'd3; 
                        end
                        
                        rf_wdata1 = rom_dout1;
                        
                        rf_waddr2 = 4'hF; 
                        rf_wdata2 = rf_wdata1;
                     end
                     
                    if (load_addr_counter > 13) 
                        next_state = STATE_PRE_PROC;
                end
                
                STATE_IDLE: begin
                    if (enable && loaded_flag) next_state = STATE_PRE_PROC;
                end
                
                STATE_PRE_PROC: begin
                    rf_raddr1 = 4'h2; 
                    rf_raddr2 = 4'h3; 
                    
                    if (rf_rdata1[31]) begin
                         alu1_cmd = 4'b0011; 
                         alu1_op1 = $signed(input_1);
                         alu1_op2 = -rf_rdata1; 
                    end else begin
                         alu1_cmd = 4'b0010; 
                         alu1_op1 = $signed(input_1);
                         alu1_op2 = $signed(rf_rdata1);
                    end
                    
                    if (rf_rdata2[31]) begin
                         alu2_cmd = 4'b0011; 
                         alu2_op1 = $signed(input_2);
                         alu2_op2 = -rf_rdata2;
                    end else begin
                         alu2_cmd = 4'b0010; 
                         alu2_op1 = $signed(input_2);
                         alu2_op2 = $signed(rf_rdata2);
                    end
                    
                    next_state = STATE_INPUT_LAYER;
                end
                
                STATE_INPUT_LAYER: begin
                    rf_raddr1 = 4'h4; 
                    rf_raddr2 = 4'h5; 
                    rf_raddr3 = 4'h6; 
                    rf_raddr4 = 4'h7; 
                    
                    mac1_op1 = inter1; 
                    mac1_op2 = $signed(rf_rdata1); 
                    mac1_op3 = $signed(rf_rdata2); 
                    
                    mac2_op1 = inter2;
                    mac2_op2 = $signed(rf_rdata3); 
                    mac2_op3 = $signed(rf_rdata4); 
                    
                    next_state = STATE_OUTPUT_LAYER;
                end
                
                STATE_OUTPUT_LAYER: begin
                    rf_raddr1 = 4'h8; 
                    rf_raddr2 = 4'h9; 
                    rf_raddr3 = 4'h0; 
                    
                    mac1_op1 = inter3;
                    mac1_op2 = $signed(rf_rdata1); 
                    mac1_op3 = $signed(rf_rdata3); 
                    

                    mac2_op1 = inter4;
                    mac2_op2 = $signed(rf_rdata2); 
                    mac2_op3 = 0; 
                    
                    next_state = STATE_POST_PROC;
                end
                
                STATE_POST_PROC: begin
                    rf_raddr1 = 4'h1; 
                    
                    if (rf_rdata1[31]) begin
                        alu1_cmd = 4'b0010; 
                        alu1_op1 = inter5;
                        alu1_op2 = -rf_rdata1; 
                    end else begin
                        alu1_cmd = 4'b0011; 
                        alu1_op1 = inter5;
                        alu1_op2 = $signed(rf_rdata1);
                    end
                    
                    next_state = STATE_IDLE;
                end
            endcase
        end 
    end

endmodule
