module weight_scm_dff (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cpu_we,
    input  wire [1:0]  cpu_bank,
    input  wire [1:0]  cpu_word,
    input  wire [31:0] cpu_wdata,
    output wire [31:0] cpu_rdata,
    input  wire [1:0]  fabric_word,
    output wire [127:0] fabric_rdata
);
    reg [31:0] mem [0:15];
    integer k;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (k=0; k<16; k=k+1) mem[k] <= 32'h0;
        end else if (cpu_we) begin
            mem[{cpu_bank, cpu_word}] <= cpu_wdata;
        end
    end

    assign cpu_rdata = mem[{cpu_bank, cpu_word}];

    assign fabric_rdata[31:0]   = mem[{2'b00, fabric_word}];
    assign fabric_rdata[63:32]  = mem[{2'b01, fabric_word}];
    assign fabric_rdata[95:64]  = mem[{2'b10, fabric_word}];
    assign fabric_rdata[127:96] = mem[{2'b11, fabric_word}];

endmodule
