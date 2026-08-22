# Verification Test Cases

This document is the pre-FPGA verification checklist for the SoC. The goal is to catch control-path, memory, and MMIO issues in simulation before running Vivado again.

## 1. Unit-Level RTL Tests

### ALU
- `make sim_alu`
- Cover ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU, MUL, MULH, DIV, DIVU, REM, REMU.
- Check zero flag behavior on a result of zero.
- Add negative-operands coverage for signed operations and divide/remainder corner cases:
  - divide by zero
  - signed overflow case (`0x80000000 / -1`)
  - large shift amounts (`operand_b[4:0]`)

### Register File
- `make sim_regfile`
- Verify single write/read, dual-read behavior, `x0` hard-wired zero, and ignored writes when `write_enable=0`.
- Add same-cycle read-after-write expectations if the microarchitecture relies on them.

### Instruction Memory
- `make sim_imem`
- Check word-aligned fetches at reset PC and subsequent instruction addresses.
- Confirm the selected `.mem` image matches the intended software test.
- Treat any unexpected `$readmemh` warnings as a setup failure.

### Data Memory
- `make sim_dmem`
- Check full-word writes, byte-enable writes, and read-data hold behavior when `read_en=0`.
- Extend with halfword writes and unaligned-access policy tests if those access types are expected in software.

### UART
- `make sim_uart`
- Verify idle line high, start bit low, status-ready deassert/reassert, and transmission completion.
- Verify RX-side behavior (`RX_valid` set, `RX_DATA` content, clear-on-read of `RX_DATA`).

### Timer
- `make sim_timer`
- Verify counter incrementing, compare-match reset behavior, interrupt generation, and disable behavior.
- Add explicit tests for:
  - compare value of zero
  - rewriting compare/control while running
  - interrupt enable cleared while timer stays enabled

### GPIO
- `make sim_gpio`
- Verify direction register read/write, output register write, input register read, and reset clearing.
- Add checks for mixed input/output bitmasks if direction is intended to be enforced later in RTL.

### PS/2 Keyboard
- `make sim_ps2_keyboard`
- Drives a simulated PS/2 device frame (start + 8 data bits LSB-first + parity + stop) over `ps2_clk`/`ps2_data`.
- Verify scan-code capture into `button_code`, `kbd_ready` assertion, `kbd_read_en` clearing `kbd_ready`, and reset behavior mid-stream.

### VGA Sync Generator
- `make sim_vga_sync`
- Verify `video_on` visible-window gating and `hsync`/`vsync` pulse timing at every region boundary (visible/front porch/sync pulse/back porch) for both the horizontal (800-cycle) and vertical (525-line) counters, plus full-frame wraparound.

### VGA Tile Lookup / Pixel Generator
- `make sim_vga_core`
- Exercises `vga_address_translator` (pixel coordinate -> 80x60 tile VRAM index) and `vga_pixel_gen` (font bit + color nibble -> RGB) directly, since both are pure combinational logic within `rtl/peripheral/vga_core.sv`.
- Covers tile-boundary addressing, the full 16-color palette, `video_on` gating, and font-bit indexing.

### VGA VRAM Controller
- `make sim_vga_vram_ctrl`
- Verify CPU-side write (100 MHz) / VGA-side registered read (25 MHz) of the same tile, the full-screen clear FSM (`vram_ready` deassertion for the duration of the clear, fill value `0x0020`), and that a CPU write attempted during a clear is dropped in favor of the clear.

## 2. CPU Regression Tests

### Broad CPU Functional Regression
- `make sim_cpu_regression`
- Current bench file: `tb/core/tb_cpu_regression.sv`
- Coverage:
  - arithmetic register results
  - store handshake assertion
  - load handshake assertion
  - memory side effects (`dmem[0]`)
  - branch not-taken behavior using `BNE x1, x1`
  - `JAL` target and link register writeback

Expected outcome today: this regression should pass as part of signoff.

### Existing CPU Smoke Test
- `make sim_cpu`
- Current bench file: `tb/core/tb_cpu.sv`
- Only proves simple register arithmetic; keep it as a fast smoke test, not as signoff coverage.

### Compiled ISA Diagnostic
- `make sim_cpu_isa`
- Software image: `sw/tests/isa_diag.S`
- Bench file: `tb/core/tb_cpu_isa_diag.sv`
- Coverage:
  - `ADDI`, `ANDI`, `ORI`, `XORI`, `SLLI`, `SRLI`, `SRAI`, `SLTI`, `SLTIU`
  - `ADD`, `SUB`, `SLT`, `SLTU`
  - `LUI`, `AUIPC`
  - `LW`, `LB`, `LBU`, `LH`, `LHU`, `SW`, `SB`, `SH`
  - `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`
  - `JAL`, `JALR`
  - `MUL`, `MULH`, `DIV`, `DIVU`, `REM`, `REMU`
  - Misaligned policy checks:
    - `LW/SW` align down to 32-bit boundary
    - `LH/LHU/SH` align down to 16-bit boundary
    - `LB/LBU/SB` remain byte-addressed
- The program writes pass/fail signatures into DMEM so failures are reported with a numbered code instead of a hang.

## 3. SoC Integration Tests

### Top-Level Decode / MMIO Mux
- `make sim_soc_decode`
- Bench file: `tb/integration/tb_soc_top_decode.sv`
- Coverage:
  - UART/timer/GPIO/7-seg/VGA/keyboard region select decode, including the VGA tile-VRAM window boundary (`0x40005000`-`0x40007580`)
  - DMEM vs MMIO read-data routing, including the VGA `vram_ready` and keyboard `{kbd_ready, kbd_scan_code}` read-data mux
  - top-level address-map sanity for `0x2000_0000` and `0x4000_xxxx`

### Full-SoC Software Diagnostic
- `make sim_soc_diag`
- Software image: `sw/tests/soc_diag.c`
- Bench file: `tb/integration/tb_soc_diag.sv`
- Coverage:
  - `.bss` initialization and stack usage
  - DMEM read/write patterns
  - GPIO direction/output writes
  - GPIO input readback via write/readback of the output register (no physical switch dependency)
  - Timer start, progress detection, and clear behavior
  - UART transmit banner (`SOC\n`)
  - final DMEM status/detail signature plus LED pattern

### Calculator Demo Integration Test
- `make sim_calculator`
- Software image: `sw/tests/calculator.c`
- Bench file: `tb/integration/tb_calculator.sv`
- Coverage:
  - ADD, MUL, SUB, DIV-by-zero, DIV result paths end-to-end
  - LED output (`gpio_write`) for each operation
  - 7-segment display register (`sevenseg_write`) for each operation
  - UART formatted output (`uart_putc`) verified byte-by-byte for ADD

## 4. Bare-Metal Software Tests

### Firmware Build Sanity
- All `.elf`, `.bin`, and `.mem` build artifacts are gitignored and regenerated on demand.
- `make compile_sw` — generic test program
- `make compile_calculator` — calculator demo
- `make compile_soc_diag` — full-SoC diagnostic
- `make compile_isa_diag` — ISA regression diagnostic
- Confirm generated `.mem` files are non-empty after each build.
- `make clean` removes all `*.elf`, `*.bin`, root-level `*.mem`, and simulation outputs.

### Software Test Programs To Add
- `boot_smoke`: initialize stack/BSS/data and write a known GPIO pattern.
- `timer_poll`: program compare value, wait for counter advance, timeout if stagnant.
- `uart_smoke`: transmit a fixed banner and a checksum byte sequence.
- `gpio_walk`: walk one-hot LED pattern and mirror switches.
- `dmem_march`: store/load patterns in DMEM to verify RAM accesses from the CPU.
- `branch_jump_isa`: small assembly program covering taken/not-taken branches, `JAL`, and `JALR`.

## 5. FPGA Bring-Up Checklist

Run `make sim_all` before every Vivado build — it covers all of the below in one command.

Only move back to Vivado after the following are true:

- All unit tests pass (`sim_alu`, `sim_mdu`, `sim_regfile`, `sim_imem`, `sim_dmem`, `sim_uart`, `sim_timer`, `sim_gpio`, `sim_sevenseg`, `sim_ps2_keyboard`, `sim_vga_sync`, `sim_vga_core`, `sim_vga_vram_ctrl`).
- `sim_cpu` and `sim_cpu_regression` pass.
- `sim_cpu_isa` passes (57 ISA diagnostic tests including RV32M).
- `sim_soc_decode` passes.
- `sim_soc_diag` passes.
- `sim_calculator` passes.
- The firmware selected for FPGA has a bounded timeout path instead of an infinite busy-wait with no observable failure signature.

**To swap firmware without re-running Vivado synthesis:**
```bash
make compile_calculator          # or compile_soc_diag, compile_isa_diag, etc.
make update_bitstream PROG=sw/tests/calculator.elf
# Then program the board with nexys_a7_top_updated.bit via Vivado Hardware Manager
```

## 6. Resolved Bugs (previously High-Risk Gaps)

All P0 and P1 bugs have been fixed. The items below were open in earlier versions of this
document; they are recorded here for audit trail. See `TODO.md` and `git log` for details.

| Item | Fix |
|------|-----|
| Double-read of MMIO on every load | Removed `mem_read=1` from STATE_WRITEBACK; added `mmio_read_data_reg` flip-flop in `soc_top.sv` |
| `soc_diag.c` fails on real FPGA at test #8 | Replaced physical-switch read with GPIO output write/readback |
| `blink_test.S` loads 0xEFFF not 0xFFFF | Replaced `lui+addi` with `addi x, x0, -1` |
| Combinational memory model in unit testbenches | Changed to `always_ff` registered reads in `tb_cpu.sv` and `tb_cpu_regression.sv` |
| `tb_cpu_regression` stores to address 0 (wrong DMEM space) | Added `lui x5, 0x20000` to use real DMEM base `0x20000000`; array indexed by `[9:2]` |
| MULHSU and MULHU untested end-to-end | Added 4 test cases to `isa_diag.S` (now 57 tests total) |
| MMIO address decode too broad | Tightened to check `dmem_addr[31:16] == 16'h4000` in `soc_top.sv` |
| DMEM decode accepts full 256 MB range | Tightened to `dmem_addr[31:14] == 18'h8000` (exact 16 KB window) |
| `fetch_en` naming backwards | Renamed to `instr_latch_en` throughout |
| Dead `alu_zero` input and `branch` output | Removed from `control_unit.sv` and `datapath.sv` |
| `alu_result_reg` has no reset | Added `if (!rst_n)` clause in `datapath.sv` |
| GPIO `direction_reg` has no effect on outputs | Changed to `assign gpio_out = output_reg & direction_reg` |
| GPIO inputs have no 2-FF synchronizer | Added `gpio_in_sync_0/sync` and `gpio_buttons_sync_0/sync` flip-flop chains |
| UART baud counter hard-wired to 10 bits | Changed to `logic [$clog2(BAUD_DIV)-1:0]` |
| CPI documentation wrong | Updated `CLAUDE.md` with per-class cycle table (multiply=6, divide=38) |
| Timer polling race in `main.c` | Replaced blocking poll with free-running counter and monotonic threshold check |

## 7. Open Gaps (P3 — future work)

These do not affect the current simulation or demo but must be addressed before adding
interrupt-driven software or OS support.

| Gap | Location | Impact |
|-----|----------|--------|
| No interrupt or exception path | Entire CPU — no CSRs, no MTVEC/MEPC/MCAUSE | ECALL, illegal instructions, misaligned access are silent no-ops; no OS or RTOS possible |
| `timer_interrupt` left unconnected | `rtl/soc_top.sv` | Timer compare-match signal is generated but never reaches the CPU |
