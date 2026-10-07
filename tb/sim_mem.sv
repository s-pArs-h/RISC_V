`default_nettype none

// Simulation memory shared by instruction and data ports (one address
// space, like a unified RAM). Writes happen on the clock edge under a byte
// mask. Addresses wrap at the memory size.
//   SYNC = 0: reads are combinational (single-cycle core)
//   SYNC = 1: read data appears one cycle after the address, like a block
//             RAM with registered output (pipelined core)
module sim_mem #(
    parameter WORDS = 16384,                 // 64 KiB
    parameter SYNC  = 0
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

    wire [31:0] imem_word = mem[imem_addr[AW+1:2]];
    wire [31:0] dmem_word = mem[dmem_addr[AW+1:2]];

    generate
        if (SYNC) begin : g_sync
            reg [31:0] imem_q, dmem_q;
            always @(posedge clk) begin
                imem_q <= imem_word;
                dmem_q <= dmem_word;
            end
            assign imem_rdata = imem_q;
            assign dmem_rdata = dmem_q;
        end else begin : g_comb
            assign imem_rdata = imem_word;
            assign dmem_rdata = dmem_word;
        end
    endgenerate

    integer b;
    always @(posedge clk) begin
        for (b = 0; b < 4; b = b + 1)
            if (dmem_wmask[b]) mem[dmem_addr[AW+1:2]][8*b +: 8] <= dmem_wdata[8*b +: 8];
    end

endmodule

`default_nettype wire
