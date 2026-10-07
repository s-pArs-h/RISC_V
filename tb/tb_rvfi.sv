`timescale 1ns/1ps
`default_nettype none

`ifndef MEM_SYNC
`define MEM_SYNC 0               // 1 for the pipelined core (block-RAM timing)
`endif
`ifndef CORE
`define CORE riscv_core
`endif

// cocotb top level: core + memory, with the RVFI trace brought out so the
// Python testbench can compare every retired instruction with the ISS.
module tb_rvfi (
    input wire clk,
    input wire rst_n
);
    wire [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wmask;
    wire        dmem_re, halted;

    wire        rvfi_valid, rvfi_trap, rvfi_halt, rvfi_intr;
    wire [63:0] rvfi_order;
    wire [31:0] rvfi_insn, rvfi_rs1_rdata, rvfi_rs2_rdata, rvfi_rd_wdata;
    wire [31:0] rvfi_pc_rdata, rvfi_pc_wdata, rvfi_mem_addr, rvfi_mem_rdata, rvfi_mem_wdata;
    wire [4:0]  rvfi_rs1_addr, rvfi_rs2_addr, rvfi_rd_addr;
    wire [3:0]  rvfi_mem_rmask, rvfi_mem_wmask;
    wire [1:0]  rvfi_mode, rvfi_ixl;

    sim_mem #(.SYNC(`MEM_SYNC)) u_mem (
        .clk(clk),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wmask(dmem_wmask),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata)
    );

    `CORE u_core (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_re(dmem_re), .dmem_wmask(dmem_wmask),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .halted(halted),
        .rvfi_valid(rvfi_valid), .rvfi_order(rvfi_order), .rvfi_insn(rvfi_insn),
        .rvfi_trap(rvfi_trap), .rvfi_halt(rvfi_halt), .rvfi_intr(rvfi_intr),
        .rvfi_mode(rvfi_mode), .rvfi_ixl(rvfi_ixl),
        .rvfi_rs1_addr(rvfi_rs1_addr), .rvfi_rs2_addr(rvfi_rs2_addr),
        .rvfi_rs1_rdata(rvfi_rs1_rdata), .rvfi_rs2_rdata(rvfi_rs2_rdata),
        .rvfi_rd_addr(rvfi_rd_addr), .rvfi_rd_wdata(rvfi_rd_wdata),
        .rvfi_pc_rdata(rvfi_pc_rdata), .rvfi_pc_wdata(rvfi_pc_wdata),
        .rvfi_mem_addr(rvfi_mem_addr), .rvfi_mem_rmask(rvfi_mem_rmask),
        .rvfi_mem_wmask(rvfi_mem_wmask), .rvfi_mem_rdata(rvfi_mem_rdata),
        .rvfi_mem_wdata(rvfi_mem_wdata)
    );
endmodule

`default_nettype wire
