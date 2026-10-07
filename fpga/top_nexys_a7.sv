`default_nettype none

// Nexys A7 (Artix-7) top level for either core.
//
//   PIPELINED = 0  single-cycle core; RAM with combinational reads
//                  (distributed RAM), 50 MHz by default
//   PIPELINED = 1  5-stage pipeline; RAM with registered reads (block RAM),
//                  100 MHz by default
//
//   clock   100 MHz board oscillator -> MMCM -> CORE_MHZ core clock
//   reset   CPU_RESETN button, synchronised to the core clock
//   memory  MEM_WORDS x 32-bit on-chip RAM loaded from INIT_FILE
//   I/O     0x8000_0000  write: LED[15:0]
//           0x8000_0004  read:  SW[15:0]
//           LED16_R lights when the core has halted (trap)
//
// Define SIM to replace the MMCM with the board clock for simulation.
module top_nexys_a7 #(
    parameter PIPELINED = 0,
    parameter MEM_WORDS = 1024,                 // 4 KiB
    parameter INIT_FILE = "demo.hex",
    /* verilator lint_off UNUSEDPARAM */
    parameter CORE_MHZ  = (PIPELINED != 0) ? 100 : 50  // unused when SIM bypasses the MMCM
    /* verilator lint_on UNUSEDPARAM */
) (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    input  wire [15:0] SW,
    output logic [15:0] LED,
    output wire        LED16_R
);
    localparam AW = $clog2(MEM_WORDS);

    // ------------------------------------------------------------------
    // Clock: MMCM, not a divider built from fabric flip-flops
    // ------------------------------------------------------------------
    wire clk;
`ifdef SIM
    assign clk = CLK100MHZ;
`else
    wire clk_mmcm, clk_fb, clk_fb_buf, locked;
    MMCME2_BASE #(
        .CLKIN1_PERIOD    (10.0),
        .CLKFBOUT_MULT_F  (10.0),               // VCO = 1000 MHz
        .CLKOUT0_DIVIDE_F (1000.0 / CORE_MHZ)
    ) u_mmcm (
        .CLKIN1(CLK100MHZ), .CLKFBIN(clk_fb_buf), .CLKFBOUT(clk_fb),
        .CLKOUT0(clk_mmcm), .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB()
    );
    BUFG u_bufg_fb  (.I(clk_fb),   .O(clk_fb_buf));
    BUFG u_bufg_clk (.I(clk_mmcm), .O(clk));
`endif

    // ------------------------------------------------------------------
    // Reset: asynchronous assert, synchronous release
    // ------------------------------------------------------------------
`ifdef SIM
    wire rst_in_n = CPU_RESETN;
`else
    wire rst_in_n = CPU_RESETN && locked;
`endif
    logic [1:0] rst_sync;
    always_ff @(posedge clk or negedge rst_in_n) begin
        if (!rst_in_n) rst_sync <= 2'b00;
        else           rst_sync <= {rst_sync[0], 1'b1};
    end
    wire rst_n = rst_sync[1];

    // ------------------------------------------------------------------
    // Core
    // ------------------------------------------------------------------
    // Only the address bits that select a RAM word or I/O are decoded, and
    // the RAM ignores read strobes, so some core outputs are unused here.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] imem_addr, dmem_addr;
    wire        dmem_re;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [31:0] imem_rdata, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wmask;
    wire        halted;

    generate
        if (PIPELINED != 0) begin : g_pipe
            riscv_pipeline u_core (
                .clk(clk), .rst_n(rst_n),
                .imem_addr(imem_addr), .imem_rdata(imem_rdata),
                .dmem_addr(dmem_addr), .dmem_re(dmem_re), .dmem_wmask(dmem_wmask),
                .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
                .halted(halted)
            );
        end else begin : g_single
            riscv_core u_core (
                .clk(clk), .rst_n(rst_n),
                .imem_addr(imem_addr), .imem_rdata(imem_rdata),
                .dmem_addr(dmem_addr), .dmem_re(dmem_re), .dmem_wmask(dmem_wmask),
                .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
                .halted(halted)
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // Memory and I/O
    // ------------------------------------------------------------------
    wire is_io = dmem_addr[31];

    logic [31:0] mem [0:MEM_WORDS-1];
    initial $readmemh(INIT_FILE, mem);

    wire [AW-1:0] iaddr = imem_addr[AW+1:2];
    wire [AW-1:0] daddr = dmem_addr[AW+1:2];

    // Writes: one byte lane per enable bit
    genvar b;
    generate
        for (b = 0; b < 4; b = b + 1) begin : g_lane
            always_ff @(posedge clk)
                if (!is_io && dmem_wmask[b]) mem[daddr][8*b +: 8] <= dmem_wdata[8*b +: 8];
        end
    endgenerate

    // Reads: combinational for the single-cycle core, registered (block RAM
    // with the I/O read registered alongside) for the pipeline
    generate
        if (PIPELINED != 0) begin : g_sync_read
            logic [31:0] imem_q, ram_q;
            logic [15:0] sw_q;
            logic        io_q;
            always_ff @(posedge clk) begin
                imem_q <= mem[iaddr];
                ram_q  <= mem[daddr];
                sw_q   <= SW;
                io_q   <= is_io;
            end
            assign imem_rdata = imem_q;
            assign dmem_rdata = io_q ? {16'h0000, sw_q} : ram_q;
        end else begin : g_comb_read
            assign imem_rdata = mem[iaddr];
            assign dmem_rdata = is_io ? {16'h0000, SW} : mem[daddr];
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                                                 LED <= 16'h0000;
        else if (is_io && dmem_wmask != 4'b0 && dmem_addr[2] == 1'b0) LED <= dmem_wdata[15:0];
    end

    assign LED16_R = halted;

endmodule

`default_nettype wire
