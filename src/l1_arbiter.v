`timescale 1ns/1ps

module l1_arbiter (
    // Master 0: DMA Engine (High Priority Streamer)
    input  wire        dma_req,
    input  wire [31:0] dma_addr,
    output reg        dma_grant,

    // Master 1: RISC-V CPU (Low Priority Configurator)
    input  wire        cpu_req,
    input  wire [31:0] cpu_addr,
    input  wire        cpu_we,
    input  wire [31:0] cpu_wdata,
    output reg        cpu_grant,

    // Slave: Weight SCM (Shared Resource)
    output reg        scm_req,
    output reg [31:0] scm_addr,
    output reg        scm_we,
    output reg [31:0] scm_wdata
);

    // FIXED PRIORITY HARDWARE ARBITRATION
    // If DMA wants the bus, it gets it instantly. CPU must wait.
    always @(*) begin
        // Default assignments (idle bus)
        dma_grant = 1'b0;
        cpu_grant = 1'b0;
        scm_req   = 1'b0;
        scm_addr  = 32'h0;
        scm_we    = 1'b0;
        scm_wdata = 32'h0;

        if (dma_req) begin
            // Grant bus to DMA
            dma_grant = 1'b1;
            scm_req   = 1'b1;
            scm_addr  = dma_addr;
            scm_we    = 1'b0; // DMA only reads
        end 
        else if (cpu_req) begin
            // Grant bus to CPU only if DMA is idle
            cpu_grant = 1'b1;
            scm_req   = 1'b1;
            scm_addr  = cpu_addr;
            scm_we    = cpu_we;
            scm_wdata = cpu_wdata;
        end
    end

endmodule
