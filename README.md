# Scalable Banked L1 Memory Fabric for Edge AI

[![](https://github.com/Vishnukumar4/tt-l1-fabric/workflows/gds/badge.svg)](https://github.com/Vishnukumar4/tt-l1-fabric/actions/workflows/gds.yaml)
[![](https://github.com/Vishnukumar4/tt-l1-fabric/workflows/docs/badge.svg)](https://github.com/Vishnukumar4/tt-l1-fabric/actions/workflows/docs.yaml)
[![](https://github.com/Vishnukumar4/tt-l1-fabric/workflows/test/badge.svg)](https://github.com/Vishnukumar4/tt-l1-fabric/actions/workflows/test.yaml)

- [Read the project documentation](docs/info.md)
- [View the GDS render](https://vishnukumar4.github.io/tt-l1-fabric/)

## What is this?

A silicon demonstrator of a scalable banked L1 weight memory fabric for edge AI accelerators, submitted to **Tiny Tapeout TTSKY26c** (Sky130A). Developed as part of an M.S. thesis at San Diego State University, SDSU IoT Laboratory.

The design contains:

- **4 independent weight banks** (4 words × 32 bits each, DFF-based)
- **Priority arbiter** granting DMA traffic over CPU access
- **DMA streaming engine** for bulk weight transfers
- **Weight-stationary GEMM MAC unit** computing dot products on streamed tiles

The same arbiter, DMA, and GEMM RTL was verified at 33-bank scale with sky130 SRAM macros through a complete Cadence RTL-to-GDS signoff flow (Xcelium, Genus, Innovus, Magic DRC = 0).

## How it works

All operations are driven through `ui_in`:

| Bits | Field | Meaning |
|------|-------|---------|
| 7:6 | mode | 00=write, 01=read, 10=DMA, 11=GEMM |
| 5:4 | bank | Bank select 0–3 |
| 3:2 | byte_sel | Byte select within 32-bit word / DMA register select |
| 1:0 | word | Word address within bank (0–3) |

- **Write** (mode=00): Drive each byte on `uio_in` (byte_sel 0,1,2,3). Commits on byte 3.
- **Read** (mode=01): Selected byte appears on `uio_out`.
- **DMA** (mode=10): byte_sel selects DMA register (0=src, 1=length, 2=start).
- **GEMM** (mode=11): byte_sel=0 reads MAC result on `uio_out` and `uo_out[3:0]`.

## How to test

25 tests verified at RTL (Xcelium) and gate-level (cocotb gl_test):

- T1–T7: Memory write/readback, all banks, all words, isolation, extremes
- T8–T9: DMA priority arbitration and CPU bus recovery
- T10: Reset clears memory and IRQs
- T11: Full DMA→GEMM end-to-end (weight 0x00030002 × 4 beats = MAC result 0x18)

## External hardware

None required. All testing uses the Tiny Tapeout demo board I/O (switches, LEDs, PMOD).

## Pinout

| Pin | Signal |
|-----|--------|
| uo_out[7] | gemm_done_irq |
| uo_out[6] | dma_done_irq |
| uo_out[5] | dma_grant |
| uo_out[4] | cpu_grant |
| uo_out[3:0] | gemm_result[3:0] |
| uio[7:0] | Data bus (input during write, output otherwise) |

## Author

Vishnukumar Varatharaja Perumal — M.S. Computer Engineering, SDSU IoT Laboratory
