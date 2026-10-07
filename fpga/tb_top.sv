`timescale 1ns/1ps
`default_nettype none

// Simulation check of the FPGA top level and demo program (compile with -DSIM).
// Sets the switches, lets the program run and checks LED[7:0] = popcount(SW).
module tb_top;
    reg clk = 0, rstn = 0;
    reg [15:0] sw;
    wire [15:0] led;
    wire halted;
    always #5 clk = ~clk;

    top_nexys_a7 #(.INIT_FILE("fpga/demo.hex")) dut (
        .CLK100MHZ(clk), .CPU_RESETN(rstn), .SW(sw), .LED(led), .LED16_R(halted)
    );

    function integer popcount(input [15:0] v);
        integer i;
        begin
            popcount = 0;
            for (i = 0; i < 16; i = i + 1) popcount = popcount + v[i];
        end
    endfunction

    integer t, errors = 0;
    reg [15:0] values [0:4];
    initial begin
        values[0] = 16'h0000; values[1] = 16'hFFFF; values[2] = 16'hA5A5;
        values[3] = 16'h0001; values[4] = 16'h8421;
        sw = 16'h0;
        #100 rstn = 1;
        for (t = 0; t < 5; t = t + 1) begin
            sw = values[t];
            #20000;                                   // 2000 cycles
            if (led[7:0] !== popcount(sw)) begin
                $display("FAIL: SW=%h LED[7:0]=%0d expected %0d", sw, led[7:0], popcount(sw));
                errors = errors + 1;
            end
        end
        if (halted) begin
            $display("FAIL: core halted");
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS: LEDs show popcount(SW), counter LED[15:8]=%h", led[15:8]);
        $finish;
    end
endmodule

`default_nettype wire
