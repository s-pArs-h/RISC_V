`timescale 1ns/1ps
`default_nettype none

`ifndef CORE
`define CORE riscv_core          // which core to test (overridden with -D)
`endif
`ifndef GP_REG
`define GP_REG u_rf.regs[3]      // where that core keeps x3 (gp)
`endif

// Stand-alone testbench for the riscv-tests ISA suite.
//   vvp sim +hex=<program.hex> [+max_cycles=N]
// Runs until the core halts (ECALL ends every test) and reads the result
// from gp (x3): 1 = pass, (n << 1) | 1 = test n failed.
module tb_isa;
    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    wire [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wmask;
    wire        dmem_re, halted;

    sim_mem u_mem (
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
        .halted(halted)
    );

    reg [1023:0] hex;
    integer max_cycles, cycles, i;
    reg [31:0] gp;

    initial begin
        if (!$value$plusargs("hex=%s", hex)) begin
            $display("ERROR: +hex=<file> is required");
            $finish;
        end
        if (!$value$plusargs("max_cycles=%d", max_cycles)) max_cycles = 200000;
        for (i = 0; i < 16384; i = i + 1) u_mem.mem[i] = 32'h0;
        $readmemh(hex, u_mem.mem);

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        cycles = 0;
        while (!halted && cycles < max_cycles) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        @(negedge clk);

        gp = u_core.`GP_REG;
        if (!halted)
            $display("RESULT TIMEOUT cycles=%0d", cycles);
        else if (gp == 32'd1)
            $display("RESULT PASS cycles=%0d", cycles);
        else if (gp[0])
            $display("RESULT FAIL test=%0d cycles=%0d", gp >> 1, cycles);
        else
            $display("RESULT TRAP during test=%0d pc=%08h insn=%08h", gp, imem_addr, imem_rdata);
        $finish;
    end
endmodule

`default_nettype wire
