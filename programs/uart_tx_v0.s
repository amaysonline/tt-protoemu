; v0 demo: send 'A' (0x41 = 0100_0001) forever using only SET, JMP and delays
; 8 ticks per bit. Needs only the v0 core.
.pin 0 pushpull
.set_base 0
.set_count 1
.clkdiv 53                  ; 50 MHz / 54 = 925.9 kHz ticks = 8 x 115740 baud
start:
    set pins, 0  [7]        ; start bit
    set pins, 1  [7]        ; bit0 = 1
    set pins, 0  [7]        ; bit1 = 0
    set pins, 0  [7]        ; bit2
    set pins, 0  [7]        ; bit3
    set pins, 0  [7]        ; bit4
    set pins, 0  [7]        ; bit5
    set pins, 1  [7]        ; bit6 = 1
    set pins, 0  [7]        ; bit7 = 0
    set pins, 1  [7]        ; stop bit
    jmp start    [7]        ; extra idle time between bytes (still high)
