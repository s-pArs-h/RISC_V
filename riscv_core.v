module riscv_core (
    input  wire        clk_i,
    input  wire        rst_n_i,    // Active-low reset (industry standard)
    
    output wire [31:0] pc_o,
    input  wire [31:0] instr_i,
    
    output wire [31:0] alu_out_o,
    output wire [31:0] mem_write_data_o,
    output wire        mem_we_o,
    output wire        mem_re_o,
    input  wire [31:0] mem_read_data_i
);

    reg  [31:0] pc_reg;
    wire [31:0] next_pc, pc_plus_4, pc_target;
    
    wire [4:0]  rs1, rs2, rd;
    wire [6:0]  opcode, funct7;
    wire [2:0]  funct3;
    
    wire        reg_write, branch, zero, pc_src;
    wire [1:0]  alu_src;
    wire [3:0]  alu_ctrl;
    
    wire [31:0] rd1, rd2, alu_b, reg_write_data;
    reg  [31:0] imm_ext;

    assign pc_o = pc_reg;

    // --- PC Logic ---
    assign pc_plus_4 = pc_reg + 32'd4;
    assign pc_target = pc_reg + imm_ext; 
    assign pc_src    = branch & zero;   
    assign next_pc   = pc_src ? pc_target : pc_plus_4;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pc_reg <= 32'b0;
        end else begin
            pc_reg <= next_pc;
        end
    end

    // --- Instruction Parsing ---
    assign opcode = instr_i[6:0];
    assign rd     = instr_i[11:7];
    assign funct3 = instr_i[14:12];
    assign rs1    = instr_i[19:15];
    assign rs2    = instr_i[24:20];
    assign funct7 = instr_i[31:25];

    // Immediate generation
    always @(*) begin
        case (opcode)
            7'b0010011, 7'b0000011: imm_ext = {{20{instr_i[31]}}, instr_i[31:20]};
            7'b0100011: imm_ext = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
            7'b1100011: imm_ext = {{20{instr_i[31]}}, instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
            default: imm_ext = 32'b0;
        endcase
    end

    // --- Sub-modules ---
    riscv_decode u_decode (
        .opcode_i   (opcode),
        .funct3_i   (funct3),
        .funct7_i   (funct7),
        .reg_write_o(reg_write),
        .mem_write_o(mem_we_o),
        .mem_read_o (mem_re_o),
        .branch_o   (branch),
        .alu_src_o  (alu_src),
        .alu_ctrl_o (alu_ctrl)
    );

    assign reg_write_data = mem_re_o ? mem_read_data_i : alu_out_o;

    riscv_regfile u_regfile (
        .clk_i (clk_i),
        .we_i  (reg_write),
        .rs1_i (rs1),
        .rs2_i (rs2),
        .rd_i  (rd),
        .wd_i  (reg_write_data),
        .rd1_o (rd1),
        .rd2_o (rd2)
    );

    assign alu_b = (alu_src == 2'b01) ? imm_ext : rd2;

    riscv_alu u_alu (
        .a_i       (rd1),
        .b_i       (alu_b),
        .alu_ctrl_i(alu_ctrl),
        .result_o  (alu_out_o),
        .zero_o    (zero)
    );

    assign mem_write_data_o = rd2;

endmodule