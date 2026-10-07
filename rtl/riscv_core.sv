`default_nettype none

// Single-cycle RV32I core.
//
// Every clock edge retires one instruction: fetch, decode, execute, memory
// and write-back all happen in the same cycle. Instruction and data memories
// are separate (Harvard) and read combinationally; stores and register
// writes happen on the clock edge.
//
// Traps: illegal instructions, ECALL/EBREAK, misaligned loads/stores and
// misaligned jump/branch targets stop the core (`halted`) without changing
// any architectural state. There are no CSRs or interrupts, so stopping is
// the defined trap behaviour of this core; test programs end with ECALL.
//
// With RISCV_FORMAL defined the core exposes the RISC-V Formal Interface
// (RVFI): one registered record per retired instruction. The cocotb
// testbench compares this trace with a Python model, and riscv-formal checks
// it against the ISA specification.
module riscv_core #(
    parameter [31:0] RESET_PC = 32'h0000_0000
) (
    input  wire         clk,
    input  wire         rst_n,

    output wire [31:0]  imem_addr,
    input  wire [31:0]  imem_rdata,

    output wire [31:0]  dmem_addr,      // word aligned
    output wire         dmem_re,
    output wire [3:0]   dmem_wmask,     // non-zero: write these byte lanes
    output wire [31:0]  dmem_wdata,
    input  wire [31:0]  dmem_rdata,

    output wire         halted
`ifdef RISCV_FORMAL
    ,
    output logic        rvfi_valid,
    output logic [63:0] rvfi_order,
    output logic [31:0] rvfi_insn,
    output logic        rvfi_trap,
    output logic        rvfi_halt,
    output logic        rvfi_intr,
    output logic [1:0]  rvfi_mode,
    output logic [1:0]  rvfi_ixl,
    output logic [4:0]  rvfi_rs1_addr,
    output logic [4:0]  rvfi_rs2_addr,
    output logic [31:0] rvfi_rs1_rdata,
    output logic [31:0] rvfi_rs2_rdata,
    output logic [4:0]  rvfi_rd_addr,
    output logic [31:0] rvfi_rd_wdata,
    output logic [31:0] rvfi_pc_rdata,
    output logic [31:0] rvfi_pc_wdata,
    output logic [31:0] rvfi_mem_addr,
    output logic [3:0]  rvfi_mem_rmask,
    output logic [3:0]  rvfi_mem_wmask,
    output logic [31:0] rvfi_mem_rdata,
    output logic [31:0] rvfi_mem_wdata
`endif
);
    `include "rv32i_defs.svh"

    // ------------------------------------------------------------------
    // Fetch
    // ------------------------------------------------------------------
    logic [31:0] pc;
    logic        halt_q;
    wire  [31:0] instr = imem_rdata;
    assign imem_addr = pc;

    wire active = rst_n && !halt_q;      // the core may change state this cycle

    // ------------------------------------------------------------------
    // Decode
    // ------------------------------------------------------------------
    wire [4:0] rs1 = instr[19:15];
    wire [4:0] rs2 = instr[24:20];
    wire [4:0] rd  = instr[11:7];
    wire [2:0] f3  = instr[14:12];

    wire [3:0] alu_op;
    wire [1:0] a_sel, wb_sel;
    wire [2:0] imm_type;
    wire       b_imm, reg_write, mem_read, mem_write, branch, jal, jalr, env_trap, illegal;

    riscv_decoder u_dec (
        .instr     (instr),
        .alu_op    (alu_op),
        .a_sel     (a_sel),
        .b_imm     (b_imm),
        .imm_type  (imm_type),
        .wb_sel    (wb_sel),
        .reg_write (reg_write),
        .mem_read  (mem_read),
        .mem_write (mem_write),
        .branch    (branch),
        .jal       (jal),
        .jalr      (jalr),
        .env_trap  (env_trap),
        .illegal   (illegal)
    );

    wire [31:0] imm;
    riscv_imm_gen u_imm (.instr(instr[31:7]), .imm_type(imm_type), .imm(imm));

    wire [31:0] rs1_data, rs2_data, wb_data;
    wire        rf_we;

    riscv_regfile u_rf (
        .clk      (clk),
        .rs1      (rs1),
        .rs2      (rs2),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .we       (rf_we),
        .rd       (rd),
        .rd_data  (wb_data)
    );

    // ------------------------------------------------------------------
    // Execute
    // ------------------------------------------------------------------
    wire [31:0] alu_a = (a_sel == A_PC)   ? pc    :
                        (a_sel == A_ZERO) ? 32'd0 : rs1_data;
    wire [31:0] alu_b = b_imm ? imm : rs2_data;
    wire [31:0] alu_y;

    riscv_alu u_alu (.a(alu_a), .b(alu_b), .op(alu_op), .y(alu_y));

    // Branch comparison
    logic br_taken;
    always @(*) begin
        case (f3)
            3'b000:  br_taken = (rs1_data == rs2_data);                     // BEQ
            3'b001:  br_taken = (rs1_data != rs2_data);                     // BNE
            3'b100:  br_taken = ($signed(rs1_data) <  $signed(rs2_data));   // BLT
            3'b101:  br_taken = ($signed(rs1_data) >= $signed(rs2_data));   // BGE
            3'b110:  br_taken = (rs1_data <  rs2_data);                     // BLTU
            3'b111:  br_taken = (rs1_data >= rs2_data);                     // BGEU
            default: br_taken = 1'b0;
        endcase
    end

    wire [31:0] pc_plus4 = pc + 32'd4;
    wire [31:0] target   = jalr ? {alu_y[31:1], 1'b0} : (pc + imm);
    wire        take     = jal || jalr || (branch && br_taken);
    wire [31:0] next_pc  = take ? target : pc_plus4;

    // ------------------------------------------------------------------
    // Memory
    // ------------------------------------------------------------------
    wire [3:0]  byte_mask;
    wire [31:0] load_data;
    wire        ls_misaligned;

    riscv_lsu u_lsu (
        .addr       (alu_y),
        .funct3     (f3),
        .store_data (rs2_data),
        .bus_rdata  (dmem_rdata),
        .bus_addr   (dmem_addr),
        .byte_mask  (byte_mask),
        .bus_wdata  (dmem_wdata),
        .load_data  (load_data),
        .misaligned (ls_misaligned)
    );

    // ------------------------------------------------------------------
    // Traps and commit
    // ------------------------------------------------------------------
    wire trap = illegal || env_trap
             || ((mem_read || mem_write) && ls_misaligned)
             || (take && target[1:0] != 2'b00);
    wire commit = active && !trap;

    assign dmem_re    = commit && mem_read;
    assign dmem_wmask = (commit && mem_write) ? byte_mask : 4'b0000;

    assign wb_data = (wb_sel == WB_MEM) ? load_data :
                     (wb_sel == WB_PC4) ? pc_plus4  : alu_y;
    assign rf_we   = commit && reg_write;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc     <= RESET_PC;
            halt_q <= 1'b0;
        end else if (!halt_q) begin
            if (trap) halt_q <= 1'b1;
            else      pc     <= next_pc;
        end
    end

    assign halted = halt_q;

    // ------------------------------------------------------------------
    // RISC-V Formal Interface: one record per retired instruction,
    // registered so it describes the instruction that just retired.
    // ------------------------------------------------------------------
`ifdef RISCV_FORMAL
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvfi_valid <= 1'b0;
            rvfi_order <= 64'd0;
        end else begin
            rvfi_valid <= active;
            if (rvfi_valid) rvfi_order <= rvfi_order + 64'd1;
        end
    end

    always_ff @(posedge clk) begin
        rvfi_insn      <= instr;
        rvfi_trap      <= trap;
        rvfi_halt      <= trap;
        rvfi_intr      <= 1'b0;
        rvfi_mode      <= 2'd3;                 // machine mode
        rvfi_ixl       <= 2'd1;                 // XLEN = 32
        rvfi_rs1_addr  <= rs1;
        rvfi_rs2_addr  <= rs2;
        rvfi_rs1_rdata <= rs1_data;
        rvfi_rs2_rdata <= rs2_data;
        rvfi_rd_addr   <= rf_we ? rd : 5'd0;
        rvfi_rd_wdata  <= (rf_we && rd != 5'd0) ? wb_data : 32'd0;
        rvfi_pc_rdata  <= pc;
        rvfi_pc_wdata  <= trap ? pc : next_pc;
        rvfi_mem_addr  <= dmem_addr;
        rvfi_mem_rmask <= dmem_re ? byte_mask : 4'b0000;
        rvfi_mem_wmask <= dmem_wmask;
        rvfi_mem_rdata <= dmem_rdata;
        rvfi_mem_wdata <= dmem_wdata;
    end
`endif

endmodule

`default_nettype wire
