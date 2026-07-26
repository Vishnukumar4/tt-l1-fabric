// ============================================================
// tt_um_vperumal_l1_fabric.v
// Tiny Tapeout TTSKY26c — Scalable L1 Memory Fabric
// Author : Vishnukumar Varatharaja Perumal, SDSU IoT Lab
// Target : 4x2 tiles, 50 MHz, sky130A
// ============================================================
module tt_um_vperumal_l1_fabric (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    // ---- I/O protocol decode --------------------------------
    // ui_in[7:6] mode: 00=write 01=read 10=DMA 11=GEMM
    // ui_in[5:4] bank select (0-3)
    // ui_in[3:2] byte_sel (which byte of 32-bit word)
    // ui_in[1:0] word address within bank (0-3)
    wire [1:0] mode     = ui_in[7:6];
    wire [1:0] bank_sel = ui_in[5:4];
    wire [1:0] byte_sel = ui_in[3:2];
    wire [1:0] word_sel = ui_in[1:0];

    // ---- Byte assembly for 32-bit write --------------------
    reg  [31:0] wr_accum;
    wire        is_write   = (mode == 2'b00) && ena;
    wire        is_read    = (mode == 2'b01) && ena;
    wire        is_dma     = (mode == 2'b10) && ena;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_accum <= 32'h0;
        end else if (is_write) begin
            case (byte_sel)
                2'b00: wr_accum[ 7: 0] <= uio_in;
                2'b01: wr_accum[15: 8] <= uio_in;
                2'b10: wr_accum[23:16] <= uio_in;
                2'b11: wr_accum[31:24] <= uio_in;
            endcase
        end
    end

    // Commit fires cycle AFTER byte_sel=11 to allow accumulator to settle
    reg commit_we_r;
    always @(posedge clk) begin
        if (!rst_n) commit_we_r <= 1'b0;
        else commit_we_r <= is_write && (byte_sel == 2'b11);
    end
    wire commit_we = commit_we_r;
    
    // Latch bank/word at commit time
    reg [1:0] commit_bank, commit_word;
    always @(posedge clk) begin
        if (!rst_n) begin
            commit_bank <= 2'h0;
            commit_word <= 2'h0;
        end else if (is_write && (byte_sel == 2'b11)) begin
            commit_bank <= bank_sel;
            commit_word <= word_sel;
        end
    end

    // ---- Read byte output ----------------------------------
    wire [31:0] cpu_rdata;
    reg  [7:0]  rd_byte;
    always @(*) begin
        case (byte_sel)
            2'b00: rd_byte = cpu_rdata[ 7: 0];
            2'b01: rd_byte = cpu_rdata[15: 8];
            2'b10: rd_byte = cpu_rdata[23:16];
            2'b11: rd_byte = cpu_rdata[31:24];
        endcase
    end

    // ---- L1 Arbiter ----------------------------------------
    wire        dma_grant, cpu_grant;
    wire        scm_req, scm_we;
    wire [31:0] scm_addr, scm_wdata_arb;
    wire [31:0] dma_scm_addr;
    wire [1:0]  arb_bank;
    wire [1:0]  arb_word;

    // Map to 32-bit addr for arbiter compatibility
    wire [31:0] cpu_addr = commit_we ?
        {26'h0, commit_bank, 2'h0, commit_word} :
        {26'h0, bank_sel,   2'h0, word_sel};
    wire [31:0] dma_addr = {26'h0, bank_sel, 2'h0, word_sel};

    l1_arbiter u_arbiter (
        .dma_req   (is_dma),
        .dma_addr  (dma_addr),
        .dma_grant (dma_grant),
        .cpu_req   (ena),
        .cpu_addr  (cpu_addr),
        .cpu_we    (commit_we),
        .cpu_wdata (wr_accum),
        .cpu_grant (cpu_grant),
        .scm_req   (scm_req),
        .scm_addr  (scm_addr),
        .scm_we    (scm_we),
        .scm_wdata (scm_wdata_arb)
    );

    // ---- Weight SCM (DFF) ----------------------------------
    wire [127:0] fabric_rdata;
    wire [31:0]  dma_scm_rdata;

    weight_scm_dff u_weight_scm (
        .clk         (clk),
        .rst_n       (rst_n),
        .cpu_we      (scm_we),
        .cpu_bank    (scm_addr[5:4]),
        .cpu_word    (scm_addr[1:0]),
        .cpu_wdata   (scm_wdata_arb),
        .cpu_rdata   (cpu_rdata),
        .fabric_word (dma_scm_addr[1:0]),
        .fabric_rdata(fabric_rdata)
    );

    // ---- DMA Engine ----------------------------------------
    wire [31:0] stream_data;
    wire        stream_valid, dma_done_irq;
    wire        gemm_stream_ready;

    dma_engine u_dma (
        .clk          (clk),
        .rst_n        (rst_n),
        .reg_addr     (cpu_addr),
        .reg_we       (is_dma),
        .reg_wdata    (wr_accum),
        .reg_rdata    (),
        .scm_addr     (dma_scm_addr),
        .scm_rdata    (fabric_rdata[31:0]),
        .stream_data  (stream_data),
        .stream_valid (stream_valid),
        .stream_ready (gemm_stream_ready),
        .dma_done_irq (dma_done_irq)
    );

    // ---- GEMM Accelerator ----------------------------------
    wire [31:0] gemm_rdata;
    wire        gemm_done_irq;

    gemm_accelerator_hetero u_gemm (
        .clk           (clk),
        .rst_n         (rst_n),
        .reg_addr      (cpu_addr),
        .reg_we        ((mode == 2'b11) && ena),
        .reg_wdata     (wr_accum),
        .reg_rdata     (gemm_rdata),
        .done_irq      (gemm_done_irq),
        .stream_wdata  (stream_data),
        .stream_wvalid (stream_valid),
        .stream_wready (gemm_stream_ready)
    );

    // ---- Outputs -------------------------------------------
    // uo_out: all bits driven — no floating outputs (TT spec)
    assign uo_out  = {gemm_done_irq, dma_done_irq,
                      dma_grant, cpu_grant,
                      gemm_rdata[3:0]};

    // uio: input during write, output during read/DMA/GEMM
    assign uio_out = is_read ? rd_byte :
                     (mode == 2'b11) ? gemm_rdata[7:0] :
                     fabric_rdata[7:0];
    assign uio_oe  = is_write ? 8'h00 : 8'hFF;

endmodule
