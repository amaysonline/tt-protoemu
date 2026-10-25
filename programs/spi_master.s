; SPI master, mode 0 (CPOL=0, CPHA=0), MSB first, one byte per CS pulse.
; SCK = pin 2 (side-set), MOSI = pin 3, MISO = pin 4, CS = pin 5. 4 ticks per SCK period.
.pin 2 pushpull
.pin 3 pushpull
.pin 4 input
.pin 5 pushpull
.side_pin 2
.out_base 3
.in_base 4
.set_base 5
.set_count 1
.out_shift msb
.in_shift msb
.clkdiv 11                  ; 50 MHz / 12 = 4.17 MHz ticks -> SCK = 1.04 MHz
init:
    set pins, 1     side 0      ; CS high, SCK low
start:
    pull            side 0      ; wait for a byte to send
    set pins, 0                 ; CS low
    set x, 7
bitloop:
    out pins, 1     side 0 [1]  ; SCK low for 2 ticks; MOSI = next bit
    in pins, 1      side 1      ; SCK rises; sample MISO
    jmp x--, bitloop side 1     ; SCK high for 2 ticks
    push noblock    side 0      ; received byte -> RX FIFO (dropped if full)
    set pins, 1                 ; CS high
    jmp start
