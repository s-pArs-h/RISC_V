module riscv_alu (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [3:0]  alu_ctrl_i,
    output reg  [31:0] result_o,
    output wire        zero_o
);

    // ALU Control Codes
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLL  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_SLT  = 4'b1000;
    localparam ALU_SLTU = 4'b1001;

    always @(*) begin
        case (alu_ctrl_i)
            ALU_ADD:  result_o = a_i + b_i;
            ALU_SUB:  result_o = a_i - b_i;
            ALU_AND:  result_o = a_i & b_i;
            ALU_OR:   result_o = a_i | b_i;
            ALU_XOR:  result_o = a_i ^ b_i;
            ALU_SLL:  result_o = a_i << b_i[4:0];
            ALU_SRL:  result_o = a_i >> b_i[4:0];
            ALU_SRA:  result_o = $signed(a_i) >>> b_i[4:0];
            ALU_SLT:  result_o = ($signed(a_i) < $signed(b_i)) ? 32'b1 : 32'b0;
            ALU_SLTU: result_o = (a_i < b_i) ? 32'b1 : 32'b0;
            default:  result_o = 32'b0;
        endcase
    end

    assign zero_o = (result_o == 32'b0);

endmodule