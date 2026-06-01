module riscv_regfile #(
    parameter DATA_WIDTH = 32
)(
    input  wire                    clk_i,
    input  wire                    we_i,
    input  wire [4:0]              rs1_i,
    input  wire [4:0]              rs2_i,
    input  wire [4:0]              rd_i,
    input  wire [DATA_WIDTH-1:0]   wd_i,
    output wire [DATA_WIDTH-1:0]   rd1_o,
    output wire [DATA_WIDTH-1:0]   rd2_o
);

    reg [DATA_WIDTH-1:0] mem [0:31];
    integer i;

    // Initialize to zero for simulation stability
    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'b0}};
        end
    end

    // x0 is hardwired to 0
    assign rd1_o = (rs1_i == 5'b0) ? {DATA_WIDTH{1'b0}} : mem[rs1_i];
    assign rd2_o = (rs2_i == 5'b0) ? {DATA_WIDTH{1'b0}} : mem[rs2_i];

    always @(posedge clk_i) begin
        if (we_i && (rd_i != 5'b0)) begin
            mem[rd_i] <= wd_i;
        end
    end

endmodule