module riscv_decode (
    input  wire [6:0] opcode_i,
    input  wire [2:0] funct3_i,
    input  wire [6:0] funct7_i,
    output reg        reg_write_o,
    output reg        mem_write_o,
    output reg        mem_read_o,
    output reg        branch_o,
    output reg  [1:0] alu_src_o,
    output reg  [3:0] alu_ctrl_o
);

    // RV32I Base Opcodes
    localparam OPC_R_TYPE = 7'b0110011;
    localparam OPC_I_TYPE = 7'b0010011;
    localparam OPC_LOAD   = 7'b0000011;
    localparam OPC_STORE  = 7'b0100011;
    localparam OPC_BRANCH = 7'b1100011;

    always @(*) begin
        // Defensive coding: default all signals to 0 to prevent latches
        reg_write_o = 1'b0;
        mem_write_o = 1'b0;
        mem_read_o  = 1'b0;
        branch_o    = 1'b0;
        alu_src_o   = 2'b00;
        alu_ctrl_o  = 4'b0000; 

        case (opcode_i)
            OPC_R_TYPE: begin
                reg_write_o = 1'b1;
                alu_src_o   = 2'b00;
                if (funct3_i == 3'b000 && funct7_i == 7'b0000000) alu_ctrl_o = 4'b0000; // ADD
                if (funct3_i == 3'b000 && funct7_i == 7'b0100000) alu_ctrl_o = 4'b0001; // SUB
                if (funct3_i == 3'b111) alu_ctrl_o = 4'b0010; // AND
                if (funct3_i == 3'b110) alu_ctrl_o = 4'b0011; // OR
            end

            OPC_I_TYPE: begin 
                reg_write_o = 1'b1;
                alu_src_o   = 2'b01; 
                if (funct3_i == 3'b000) alu_ctrl_o = 4'b0000; // ADDI
            end
            
            OPC_LOAD: begin 
                reg_write_o = 1'b1;
                mem_read_o  = 1'b1;
                alu_src_o   = 2'b01;
                alu_ctrl_o  = 4'b0000; 
            end

            OPC_STORE: begin
                mem_write_o = 1'b1;
                alu_src_o   = 2'b01;
                alu_ctrl_o  = 4'b0000; 
            end

            OPC_BRANCH: begin
                branch_o   = 1'b1;
                alu_src_o  = 2'b00;
                alu_ctrl_o = 4'b0001; // SUB to check equality
            end
            
            default: ; 
        endcase
    end
endmodule