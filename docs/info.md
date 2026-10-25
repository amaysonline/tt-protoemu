<!---
This file is used to generate the project datasheet.
-->

## How it works

This is a programmable protocol engine: a tiny I/O processor that will run UART, SPI and I2C as
programs instead of fixed hardware. It is our entry to Jane Street's protocol emulator ASIC challenge.

The current version (Phase 0) is a hard-wired UART transmitter used to bring up the design flow.
It sends the byte on `ui_in[7:0]` over and over on `uo_out[0]` at 115200 baud, 8 data bits,
no parity, 1 stop bit (8N1), least significant bit first. A baud generator divides the 50 MHz clock
into a 16x oversampling tick, and the transmitter holds each bit for 16 ticks.

## How to test

1. Run the clock at 50 MHz and release reset.
2. Set the input switches `ui_in[7:0]` to a byte, for example `0x41` (the letter A).
3. Connect `uo_out[0]` to the RX pin of a 3.3 V USB-to-UART adapter, and join the grounds.
4. Open a serial terminal at 115200 baud, 8N1. The character repeats continuously.

## External hardware

A 3.3 V USB-to-UART adapter (for example CP2102 or CH340) and a serial terminal on a computer.
