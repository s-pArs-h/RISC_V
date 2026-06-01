`timescale 1ns / 1ps

module tb_simple;

    // 1. Testbench Signals
    reg         clk;
    reg         rst_n;
    
    wire [31:0] pc;
    reg  [31:0] instr;
    wire [31:0] alu_out;
    wire [31:0] mem_write_data;
    wire        mem_we;
    wire        mem_re;
    reg  [31:0] mem_read_data;

    // 2. Small Embedded Memories (16 words each)
    reg [31:0] imem [0:15]; // Instruction Memory
    reg [31:0] dmem [0:15]; // Data Memory

    // 3. Instantiate the Processor Core
    riscv_core dut (
        .clk_i            (clk),
        .rst_n_i          (rst_n),
        .pc_o             (pc),
        .instr_i          (instr),
        .alu_out_o        (alu_out),
        .mem_write_data_o (mem_write_data),
        .mem_we_o         (mem_we),
        .mem_re_o         (mem_re),
        .mem_read_data_i  (mem_read_data)
    );

    // 4. Clock Generation (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 5. Memory Routing Logic
    // Asynchronous Instruction Fetch (ignoring bottom 2 bits for word alignment)
    always @(*) instr = imem[pc[5:2]]; 
    
    // Synchronous Data Write
    always @(posedge clk) begin
        if (mem_we) dmem[alu_out[5:2]] <= mem_write_data;
    end
    
    // Asynchronous Data Read
    always @(*) mem_read_data = dmem[alu_out[5:2]];

    // 6. Main Simulation Sequence
    initial begin
        // Load the hardcoded program into Instruction Memory
        imem[0] = 32'h00500093; // addi x1, x0, 5   (x1 = 5)
        imem[1] = 32'h00a00113; // addi x2, x0, 10  (x2 = 10)
        imem[2] = 32'h002081b3; // add x3, x1, x2   (x3 = 15)
        imem[3] = 32'h00302023; // sw x3, 0(x0)     (Store 15 to address 0)
        imem[4] = 32'h00000063; // beq x0, x0, 0    (Infinite loop / End program)

        // Initialize Data Memory address 0
        dmem[0] = 32'd0;

        // Apply Reset
        rst_n = 0;
        #15;
        rst_n = 1;

        // Wait enough clock cycles for the 5 instructions to execute
        #60;

        // Verify the final result stored in memory
        $display("-----------------------------------------");
        $display("Final value in dmem[0]: %0d", dmem[0]);
        
        if (dmem[0] == 32'd15)
            $display("TEST STATUS: PASSED!");
        else
            $display("TEST STATUS: FAILED!");
        $display("-----------------------------------------");
        
        // Stop simulation
        $finish;
    end

    // 7. Dump Waveforms (Optional, for viewing in GTKWave)
    initial begin
        $dumpfile("simple_tb.vcd");
        $dumpvars(0, tb_simple);
    end

endmodule