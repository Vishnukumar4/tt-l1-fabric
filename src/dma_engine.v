/*
 * Copyright (c) 2026 Vishnukumar Varatharaja Perumal
 * SPDX-License-Identifier: Apache-2.0
 */


module dma_engine (
    input  wire          clk,
    input  wire          rst_n,

    // CPU Configuration Interface (MMIO)
    input  wire [31:0]   reg_addr,
    input  wire          reg_we,
    input  wire [31:0]   reg_wdata,
    output reg [31:0]   reg_rdata,

    // Fabric Read Port (To Weight SCM)
    output wire [31:0]   scm_addr,
    input  wire [1023:0] scm_rdata,

    // Stream Write Port
    output wire [1023:0] stream_data,
    output reg          stream_valid,
    input  wire          stream_ready,

    // Interrupt
    output reg          dma_done_irq
);

    // DMA Configuration Registers
    reg [31:0] src_addr_reg;
    reg [31:0] length_reg;
    reg        start_reg;
    reg        busy;

    // MMIO Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_addr_reg <= 32'h0;
            length_reg   <= 32'h0;
            start_reg    <= 1'b0;
        end else begin
            start_reg <= 1'b0; 
            if (reg_we) begin
                case (reg_addr[7:0])
                    8'h00: src_addr_reg <= reg_wdata;
                    8'h04: length_reg   <= reg_wdata;
                    8'h08: start_reg    <= reg_wdata[0];
                endcase
            end
        end
    end

    // MMIO Read Mux
    always @(*) begin
        reg_rdata = 32'h0;
        case (reg_addr[7:0])
            8'h00: reg_rdata = src_addr_reg;
            8'h04: reg_rdata = length_reg;
            8'h08: reg_rdata = {31'b0, busy};
        endcase
    end

    // DMA State Machine
    localparam [1:0] IDLE  = 2'b00,
                     FETCH = 2'b01,
                     PUSH  = 2'b10;
    reg [1:0] state, next_state;

    reg [31:0] current_addr;
    reg [31:0] words_left;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            current_addr <= 32'h0;
            words_left   <= 32'h0;
            dma_done_irq <= 1'b0; // FIX: Registered IRQ
        end else begin
            state <= next_state;
            dma_done_irq <= 1'b0; // Default pulse behavior

            if (state == IDLE && start_reg) begin
                current_addr <= src_addr_reg;
                words_left   <= length_reg;
            end else if (state == PUSH && stream_ready && stream_valid) begin
                current_addr <= current_addr + 32'h80;
                words_left   <= words_left - 32'd1;
                
                if (words_left == 32'd1) begin
                    dma_done_irq <= 1'b1; // Trigger on last transfer
                end
            end
        end
    end

    always @(*) begin
        next_state   = state;
        busy         = 1'b1;
        stream_valid = 1'b0;

        case (state)
            IDLE: begin
                busy = 1'b0;
                if (start_reg && length_reg > 32'd0) next_state = FETCH;
            end
            FETCH: begin
                next_state = PUSH;
            end
            PUSH: begin
                stream_valid = 1'b1;
                if (stream_ready) begin
                    next_state = (words_left == 32'd1) ? IDLE : FETCH;
                end
            end
        endcase
    end

    assign scm_addr    = current_addr;
    assign stream_data = scm_rdata;

endmodule
