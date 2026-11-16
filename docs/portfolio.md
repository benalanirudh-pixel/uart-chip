# Portfolio copy

## LinkedIn post (about 150 words)

I just took a UART controller from Verilog all the way to a checked chip layout, using only open-source tools.

What is in it: a baud generator, transmitter, 16x-oversampling receiver and two 8-byte FIFOs, with framing-error and overrun flags.

How I checked it:
- 10 cocotb tests, including all 256 byte values in loopback and 200 random bytes with random gaps
- a formal proof of the FIFO (SymbiYosys), plus deliberately broken versions to confirm the tests and the proof actually catch bugs
- a full RTL-to-GDS run in GitHub Actions on the IHP SG13 process via Tiny Tapeout: setup and hold met, DRC, LVS and antenna clean

One honest lesson: my first build did not fit a 1x1 tile (95% utilisation, placement failed), so I moved to 1x2.

Not done: silicon, FPGA test, parity or flow control.

Code, tests and layout: https://github.com/benalanirudh-pixel/uart-chip

#VLSI #Verilog #OpenSource #ASIC #TinyTapeout

## Fiverr / Upwork gig description

**Title:** UART / SPI / I2C IP core in Verilog with cocotb testbench and GDS

I will design a serial-interface IP block (UART, SPI or I2C) in clean, synthesizable Verilog-2005 and prove that it works.

**What you get**
- RTL: simple, readable, one module per file, no latches, single clock, synchronous reset
- cocotb testbench with directed and random tests, scoreboard checking, and waveforms (FST)
- Verilator lint-clean code
- Formal proofs (SymbiYosys) for FIFOs or other key blocks, when relevant
- GitHub Actions that run the tests and the full RTL-to-GDS flow (open-source, Tiny Tapeout / LibreLane)
- A short spec with register map, pin map, timing diagram, and a results report (cell count, area, timing slack, DRC/LVS)

**Reference project:** UART with 16x oversampling RX, 8-byte FIFOs, framing/overrun flags, 10 passing tests, FIFO formal proof, and a clean IHP SG13 layout. https://github.com/benalanirudh-pixel/uart-chip

**What I need from you:** the protocol and features you want, target clock, and the process or flow if it is not Tiny Tapeout.

Not included unless agreed: silicon bring-up, FPGA board testing, analog work.
