/*
 * Copyright (c) 2026 Vishnukumar Varatharaja Perumal
 * SPDX-License-Identifier: Apache-2.0
 */


module gemm_accelerator_hetero (
    input  wire          clk,
    input  wire          rst_n,

    // CPU MMIO
    input  wire [31:0]   reg_addr,
    input  wire          reg_we,
    input  wire [31:0]   reg_wdata,
    output reg  [31:0]   reg_rdata,
    output reg           done_irq,

    // AXI Stream Input (32-bit words, 4 words = 1 tile row)
    input  wire [31:0]   stream_wdata,
    input  wire          stream_wvalid,
    output wire          stream_wready
);

    // ==========================================
    // L1 PING-PONG BANKS (4 rows x 32-bit each)
    // ==========================================
    reg [31:0] bank_A [0:3];
    reg [31:0] bank_B [0:3];

    reg [1:0]  write_ptr;
    reg        active_write_bank; // 0=A, 1=B
    reg        tile_full;         // pulses 1 cycle when 4 words received

    assign stream_wready = 1'b1;

    // Single always block: write pointer + bank fill + tile_full flag
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr         <= 2'b00;
            active_write_bank <= 1'b0;
            tile_full         <= 1'b0;
            bank_A[0] <= 32'h0; bank_A[1] <= 32'h0;
            bank_A[2] <= 32'h0; bank_A[3] <= 32'h0;
            bank_B[0] <= 32'h0; bank_B[1] <= 32'h0;
            bank_B[2] <= 32'h0; bank_B[3] <= 32'h0;
        end else begin
            tile_full <= 1'b0; // default: no tile this cycle

            if (stream_wvalid && stream_wready) begin
`ifndef SYNTHESIS
                $display("[%0t ns] [GEMM L1] Streaming into Bank %s Row %0d data=0x%08x",
                          $time, active_write_bank ? "B" : "A", write_ptr, stream_wdata);
`endif

                if (active_write_bank == 1'b0) bank_A[write_ptr] <= stream_wdata;
                else                           bank_B[write_ptr] <= stream_wdata;

                if (write_ptr == 2'b11) begin
                    write_ptr         <= 2'b00;
                    active_write_bank <= ~active_write_bank;
                    tile_full         <= 1'b1; // tile complete -- MAC can fire next cycle
`ifndef SYNTHESIS
                    $display("[%0t ns] [GEMM L1] Tile FULL -- swapping banks", $time);
`endif
                end else begin
                    write_ptr <= write_ptr + 2'b01;
                end
            end
        end
    end

    // MAC result register
    reg [31:0] computed_mac_result;

    // MAC compute: fires one cycle after tile_full
    // Uses the bank that was JUST filled (opposite of active_write_bank)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            computed_mac_result <= 32'h0;
            done_irq            <= 1'b0;
        end else begin
            // CPU can clear done_irq
            if (reg_we && (reg_addr == 32'h00005004))
                done_irq <= reg_wdata[0];

            // MAC fires cycle after tile_full
            if (tile_full) begin
                // Compute dot product on the bank that was just written
                // active_write_bank already swapped, so completed bank = active_write_bank
                if (active_write_bank == 1'b1) begin
                    // Bank A was just completed
`ifndef SYNTHESIS
                    $display("[%0t ns] [GEMM MAC] Computing on Bank A", $time);
`endif
                    computed_mac_result <= computed_mac_result +
                        (bank_A[0][15:0] * bank_A[0][31:16]) +
                        (bank_A[1][15:0] * bank_A[1][31:16]) +
                        (bank_A[2][15:0] * bank_A[2][31:16]) +
                        (bank_A[3][15:0] * bank_A[3][31:16]);
                end else begin
                    // Bank B was just completed
`ifndef SYNTHESIS
                    $display("[%0t ns] [GEMM MAC] Computing on Bank B", $time);
`endif
                    computed_mac_result <= computed_mac_result +
                        (bank_B[0][15:0] * bank_B[0][31:16]) +
                        (bank_B[1][15:0] * bank_B[1][31:16]) +
                        (bank_B[2][15:0] * bank_B[2][31:16]) +
                        (bank_B[3][15:0] * bank_B[3][31:16]);
                end
                done_irq <= 1'b1;
            end
        end
    end

    // MMIO Read
    always @(*) begin
        reg_rdata = 32'h0;
        if      (reg_addr == 32'h00005000) reg_rdata = computed_mac_result;
        else if (reg_addr == 32'h00005004) reg_rdata = {31'd0, done_irq};
    end

endmodule
