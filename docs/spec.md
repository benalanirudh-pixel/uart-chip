# UART Controller – Specification (v0.1, DRAFT for approval)

Top module: `tt_um_anirudh_uart`
Target: Tiny Tapeout IHP (template `ttihp-verilog-template`, workflow tag `ttihp27a`), tile 1x1.
Language: synthesizable Verilog-2005. One clock `clk`, synchronous active-low reset `rst_n`.

## 1. Features

| Item | Value |
|------|-------|
| Frame format | 8N1: 1 start bit (0), 8 data bits LSB first, 1 stop bit (1), no parity |
| RX oversampling | 16x, start bit confirmed and every bit sampled at its middle |
| Baud rate | programmable 16-bit divider |
| TX FIFO | 8 bytes |
| RX FIFO | 8 bytes |
| Flags | framing error (sticky), RX overrun (sticky), TX write-rejected (sticky) |
| Input safety | 2-flop synchronizers on RXD and all host-bus inputs |
| Host interface | 8-bit parallel bus, 2 address bits, WR and RD strobes (MCU-driven) |

## 2. Clock, baud rate and divider math

- Default clock: **50 MHz** (matches template `CLOCK_PERIOD: 20` ns).
- The baud generator makes a **16x tick**: one tick every `DIV` clocks.

```
baud = f_clk / (16 * DIV)          DIV = round(f_clk / (16 * baud))
```

- Default: 50 000 000 / (16 * 115 200) = 27.13, so `DIV = 27` (reset value).
  Actual baud = 50 000 000 / (16 * 27) = 115 740.7, error **+0.47 %** (RX tolerance is about ±3 %, fine).
- Other examples at 50 MHz: 9600 baud -> DIV = 326 (error +0.02 %); 57600 -> DIV = 54 (error +0.47 %).
- `DIV` is 16 bits (1..65535). `DIV = 0` is treated as 1.
- Real Tiny Tapeout boards may run slower than 50 MHz. Choose DIV for the real clock.

## 3. Pin map

Follows the Tiny Tapeout "UART to USB" convention (`ui_in[3]` = RX, `uo_out[4]` = TX) so the demo-board RP2040 can act as a USB serial console.

| Pin | Dir | Name | Function |
|-----|-----|------|----------|
| `ui_in[0]` | in | WR | Host write strobe (rising edge = write) |
| `ui_in[1]` | in | RD | Host read strobe (rising edge = read; chip drives bus while high) |
| `ui_in[2]` | in | – | unused |
| `ui_in[3]` | in | RXD | UART receive line (TT convention) |
| `ui_in[5:4]` | in | ADDR[1:0] | Register address |
| `ui_in[7:6]` | in | – | unused |
| `uo_out[0]` | out | RX_AVAIL | 1 = RX FIFO not empty (usable as interrupt) |
| `uo_out[1]` | out | TX_READY | 1 = TX FIFO not full |
| `uo_out[2]` | out | OVERRUN | sticky overrun flag |
| `uo_out[3]` | out | FRAME_ERR | sticky framing-error flag |
| `uo_out[4]` | out | TXD | UART transmit line (TT convention), idle = 1 |
| `uo_out[5]` | out | TX_BUSY | 1 = shifter sending or TX FIFO not empty |
| `uo_out[6]` | out | RX_FULL | 1 = RX FIFO full |
| `uo_out[7]` | out | – | tied 0 |
| `uio[7:0]` | bidir | D[7:0] | Host data bus. MCU drives it on writes; chip drives it only while RD is high (`uio_oe` = 8'hFF), otherwise `uio_oe` = 0 |

`ena` is ignored. Unused outputs are 0.

## 4. Host interface

### Registers (selected by ADDR)

| ADDR | Name | Read | Write |
|------|------|------|-------|
| 0 | DATA | pop one byte from RX FIFO (0 if empty) | push one byte to TX FIFO (flag `TX_REJ` if full, byte dropped) |
| 1 | STATUS | status bits (below) | write-1-to-clear for bits 7:5 |
| 2 | DIV_LO | DIV[7:0] | DIV[7:0] |
| 3 | DIV_HI | DIV[15:8] | DIV[15:8] |

### STATUS bits

| Bit | Name | Meaning |
|-----|------|---------|
| 0 | RX_AVAIL | RX FIFO not empty |
| 1 | TX_READY | TX FIFO not full |
| 2 | TX_BUSY | transmitter shifting, or TX FIFO not empty |
| 3 | RX_FULL | RX FIFO full (8 bytes) |
| 4 | TX_EMPTY | TX FIFO empty and shifter idle |
| 5 | TX_REJ | sticky: a write hit a full TX FIFO and was dropped |
| 6 | FRAME_ERR | sticky: a received frame had stop bit = 0 |
| 7 | OVERRUN | sticky: a byte arrived while RX FIFO was full and was dropped |

Sticky bits clear on reset or when STATUS is written with a 1 in that bit.
A byte with a bad stop bit is still pushed to the RX FIFO (and FRAME_ERR is set).

### Bus protocol

All of `ui_in[5:0]` and `uio_in` go through 2-flop synchronizers (same latency for all bits). The chip acts on the **rising edge of the synchronized strobe**.

- **Write:** put ADDR and D on the pins, wait, raise WR for >= 4 clk, lower WR. ADDR and D must be stable from >= 4 clk before to >= 4 clk after WR rises. The chip samples ADDR/D once, on the synchronized WR rising edge.
- **Read:** put ADDR on the pins, wait >= 4 clk, raise RD. After the rising edge the chip latches the register value, pops the RX FIFO if ADDR=0, and drives it on `uio` for as long as RD stays high. MCU samples `uio` >= 6 clk after RD rises, then lowers RD. Keep RD low >= 4 clk before the next read.
- WR and RD must not be high at the same time (RD wins; WR ignored).
- At 50 MHz, 4 clk = 80 ns, so any MCU meets this easily.

## 5. Block diagram

```
                       tt_um_anirudh_uart
  ui_in[0] WR  --+
  ui_in[1] RD  --+--> [2FF sync] --> edge detect --+
  ui_in[5:4] A --+                                 |
  uio_in D[7:0]--+                                 v
                                            +-------------+   wr_data
                                            | host regs / |-----------> [TX FIFO 8x8] --> [uart_tx] --> uo_out[4] TXD
                                            | decode      |  push/pop                          ^
  uio_out D <---- read mux <----------------|  + status   |<---------- [RX FIFO 8x8] <-- [uart_rx] <-- [2FF sync] <-- ui_in[3] RXD
  uio_oe = RD                               +------+------+                    ^                ^
                                                   | DIV[15:0]                 |                |
                                                   v                           |                |
                                            [baud_gen] --- tick16 -------------+----------------+
  uo_out[0..3,5,6] <-- status flags
```

Modules: `baud_gen`, `uart_tx`, `uart_rx`, `sync_fifo` (x2), and the top level that holds the host register logic and synchronizers.

## 6. Timing of one frame (8N1, byte 0x55 = 01010101)

One bit = 16 ticks of the 16x tick = 16 * DIV clocks.

```
TXD  ‾‾‾‾|__START__|_D0=1_|_D1=0_|_D2=1_|_D3=0_|_D4=1_|_D5=0_|_D6=1_|_D7=0_|‾‾STOP‾‾‾‾‾
idle      0        1      0      1      0      1      0      1      0      1   idle
          |<-1 bit->|
RX sample:      ^mid-start (tick 8), then every 16 ticks: ^D0 ^D1 ... ^D7 ^STOP
```

RX: falling edge on synchronized RXD starts a count. At tick 8 the start bit is re-checked (still 0, else it was a glitch and is ignored). Then every 16 ticks the line is sampled (middle of each bit): 8 data bits (LSB first), then the stop bit. Stop = 1 is OK, stop = 0 sets FRAME_ERR. The receiver is ready for the next start bit after the stop-bit sample.

## 7. Behaviour rules

- TX: when TX FIFO is not empty and the shifter is idle, pop a byte and send the frame. Back-to-back frames have no extra idle time.
- RX FIFO full and a new byte arrives: drop the new byte, set OVERRUN. Older bytes stay.
- FIFO: write when full and read when empty are ignored inside `sync_fifo` (never corrupt state).
- Reset (`rst_n` = 0): FIFOs empty, flags clear, TXD = 1, DIV = 27.

## 8. Open questions for review

1. 16-bit divider (two registers) vs 8-bit (one register, minimum baud about 12 k at 50 MHz). Proposed: 16-bit.
2. Bad-stop-bit byte is kept in the FIFO. OK?
3. No parity, no hardware flow control (CTS/RTS), no interrupt pin beyond `RX_AVAIL`. OK for v1?
