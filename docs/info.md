## How it works

This project is a silicon demonstrator of a scalable banked L1 weight
memory fabric for edge AI accelerators, developed as part of an M.S.
thesis at San Diego State University (SDSU IoT Laboratory).

The design contains four independent 4-word x 32-bit weight banks
(DFF-based), a priority arbiter that grants DMA traffic priority over
CPU access, a DMA streaming engine, and a weight-stationary GEMM MAC
unit. The same arbiter, DMA, and GEMM RTL was verified at 33-bank
scale with sky130 SRAM macros through a complete Cadence
RTL-to-GDS flow (Xcelium, Genus, Innovus, Magic DRC = 0).

Writes assemble 32-bit words one byte at a time through the
bidirectional bus; a write commits when byte 3 is written. Reads are
combinational: select mode=read with a bank/word/byte address and the
selected byte appears on the bidirectional bus.

## How to test

All operations are driven through ui_in:

| Bits | Field | Meaning |
|------|-------|---------|
| 7:6  | mode  | 00=write 01=read 10=DMA 11=GEMM |
| 5:4  | bank  | bank select 0-3 |
| 3:2  | byte  | byte select within 32-bit word |
| 1:0  | word  | word address within bank |

Write a word: mode=00, drive each byte on uio (byte_sel 0,1,2,3).
The write commits on byte 3. Read it back with mode=01: the selected
byte appears on uio_out. Trigger DMA with mode=10 and observe
dma_grant (uo_out[5]) assert while cpu_grant (uo_out[4]) drops.

## External hardware

None required. All testing is done through the Tiny Tapeout demo
board I/O.
