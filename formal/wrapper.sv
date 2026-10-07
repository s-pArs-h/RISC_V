// riscv-formal wrapper: instruction and data memory read data are free
// inputs (any value, any cycle), so every check holds for every possible
// program and every possible memory content.
module rvfi_wrapper (
    input clock,
    input reset,
    `RVFI_OUTPUTS
);
    (* keep *) `rvformal_rand_reg [31:0] imem_rdata;
    (* keep *) `rvformal_rand_reg [31:0] dmem_rdata;

    (* keep *) wire [31:0] imem_addr;
    (* keep *) wire [31:0] dmem_addr;
    (* keep *) wire        dmem_re;
    (* keep *) wire [3:0]  dmem_wmask;
    (* keep *) wire [31:0] dmem_wdata;
    (* keep *) wire        halted;

    `RISCV_CORE uut (
        .clk        (clock),
        .rst_n      (!reset),
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        .dmem_addr  (dmem_addr),
        .dmem_re    (dmem_re),
        .dmem_wmask (dmem_wmask),
        .dmem_wdata (dmem_wdata),
        .dmem_rdata (dmem_rdata),
        .halted     (halted),
        `RVFI_CONN32
    );
endmodule
