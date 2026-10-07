`default_nettype none

// Simulation memory shared by instruction and data ports (one address
// space, like a unified RAM). Both reads are combinational; writes happen on
// the clock edge under a byte mask. Addresses wrap at the memory size.
module sim_mem #(
    parameter WORDS = 16384                  // 64 KiB
) (
    input  wire        clk,
    input  wire [31:0] imem_addr,
    output wire [31:0] imem_rdata,
    input  wire [31:0] dmem_addr,
    input  wire [3:0]  dmem_wmask,
    input  wire [31:0] dmem_wdata,
    output wire [31:0] dmem_rdata
);
    localparam AW = $clog2(WORDS);

    reg [31:0] mem [0:WORDS-1];

    assign imem_rdata = mem[imem_addr[AW+1:2]];
    assign dmem_rdata = mem[dmem_addr[AW+1:2]];

    integer b;
    always @(posedge clk) begin
        for (b = 0; b < 4; b = b + 1)
            if (dmem_wmask[b]) mem[dmem_addr[AW+1:2]][8*b +: 8] <= dmem_wdata[8*b +: 8];
    end

endmodule

`default_nettype wire
