# SPDX-License-Identifier: Apache-2.0
# Blackbox tests for tt_um_vperumal_l1_fabric — pin-level only
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, Timer

IDLE = 0x55  # mode=01 read, harmless

async def write_byte(dut, bank, word, byte_sel, data):
    await FallingEdge(dut.clk)
    dut.ui_in.value = (0b00 << 6) | (bank << 4) | (byte_sel << 2) | word
    dut.uio_in.value = data
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = IDLE
    dut.uio_in.value = 0

async def write_word(dut, bank, word, value):
    for b in range(4):
        await write_byte(dut, bank, word, b, (value >> (8*b)) & 0xFF)
    await ClockCycles(dut.clk, 3)

async def read_word(dut, bank, word):
    value = 0
    for b in range(4):
        await FallingEdge(dut.clk)
        dut.ui_in.value = (0b01 << 6) | (bank << 4) | (b << 2) | word
        await Timer(500, units="ns")
        value |= int(dut.uio_out.value) << (8*b)
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = IDLE
        await ClockCycles(dut.clk, 2)
    return value

async def dma_cmd(dut, bsel):
    from cocotb.triggers import FallingEdge, ClockCycles
    await FallingEdge(dut.clk)
    dut.ui_in.value = (0b10 << 6) | (0b00 << 4) | (bsel << 2) | 0b00
    await ClockCycles(dut.clk, 2)
    await FallingEdge(dut.clk)
    dut.ui_in.value = IDLE
    await ClockCycles(dut.clk, 2)

@cocotb.test()
async def test_l1_fabric(dut):
    clock = Clock(dut.clk, 20, units="us")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = IDLE
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 20)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    # T1: reset state
    assert await read_word(dut, 0, 0) == 0
    assert await read_word(dut, 3, 3) == 0

    # T2: write/readback
    await write_word(dut, 0, 0, 0xDEADBEEF)
    assert await read_word(dut, 0, 0) == 0xDEADBEEF

    # T3: all four banks
    vals = [0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC, 0xDDDDDDDD]
    for bank, v in enumerate(vals):
        await write_word(dut, bank, 0, v)
    for bank, v in enumerate(vals):
        assert await read_word(dut, bank, 0) == v

    # T4: all four words in bank 0
    for w in range(4):
        await write_word(dut, 0, w, 0x11111111 * (w + 1))
    for w in range(4):
        assert await read_word(dut, 0, w) == 0x11111111 * (w + 1)

    # T5: bank isolation
    await write_word(dut, 0, 0, 0xDEAD0000)
    assert await read_word(dut, 1, 0) == 0xBBBBBBBB

    # T6/T7: extremes
    await write_word(dut, 0, 0, 0x00000000)
    assert await read_word(dut, 0, 0) == 0x00000000
    await write_word(dut, 0, 0, 0xFFFFFFFF)
    assert await read_word(dut, 0, 0) == 0xFFFFFFFF

    # T8: DMA priority
    dut.ui_in.value = IDLE
    await ClockCycles(dut.clk, 5)
    await FallingEdge(dut.clk)
    dut.ui_in.value = 0x80
    await ClockCycles(dut.clk, 3)
    await Timer(500, units="ns")
    out = int(dut.uo_out.value)
    assert (out >> 5) & 1 == 1, "dma_grant not asserted"
    assert (out >> 4) & 1 == 0, "cpu_grant not released"

    # T9: recovery
    dut.ui_in.value = IDLE
    await ClockCycles(dut.clk, 3)
    await Timer(500, units="ns")
    out = int(dut.uo_out.value)
    assert (out >> 4) & 1 == 1
    assert (out >> 5) & 1 == 0

    # T10: reset recovery
    await write_word(dut, 0, 0, 0xCAFEBABE)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    assert await read_word(dut, 0, 0) == 0
    out = int(dut.uo_out.value)
    assert (out >> 6) & 1 == 0 and (out >> 7) & 1 == 0

    # T11: GEMM end-to-end — DMA streams bank0 into MAC
    await write_word(dut, 0, 0, 0x00030002)   # weight: 2*3=6 per beat
    await write_word(dut, 3, 3, 0x00000000)   # wr_accum := 0
    await dma_cmd(dut, 0)                     # DMA reg 0x00: src = 0
    await write_word(dut, 3, 3, 0x00000004)   # wr_accum := 4
    await dma_cmd(dut, 1)                     # DMA reg 0x04: length = 4
    await write_word(dut, 3, 3, 0x00000001)   # wr_accum := 1
    await dma_cmd(dut, 2)                     # DMA reg 0x08: START
    await ClockCycles(dut.clk, 30)            # 4 beats + MAC latency
    out = int(dut.uo_out.value)
    assert (out >> 7) & 1 == 1, "gemm_done_irq did not fire"
    await FallingEdge(dut.clk)
    dut.ui_in.value = 0xC0                    # GEMM mode, byte_sel=0
    await Timer(500, units="ns")
    assert int(dut.uio_out.value) == 0x18, \
        f"MAC result byte {hex(int(dut.uio_out.value))} != 0x18"
    assert (int(dut.uo_out.value) & 0xF) == 0x8, "gemm_result nibble != 8"
    dut.ui_in.value = IDLE

    dut._log.info("ALL COCOTB TESTS PASSED")
