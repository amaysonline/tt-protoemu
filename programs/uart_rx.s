; UART receiver, 8N1, LSB first. RX = pin 1. 8 ticks per bit.
; A bad stop bit raises IRQ and the byte is thrown away.
.pin 1 input
.in_base 1
.jmp_pin 1
.in_shift lsb
.clkdiv 53
start:
    wait 0 pin 1                ; start bit's falling edge (tick t0)
    set x, 7               [7]  ; 8 ticks
    nop                    [2]  ; 3 more: first sample lands at t0+12, mid bit 0
bitloop:
    in pins, 1                  ; sample one bit into the ISR
    jmp x--, bitloop       [6]  ; 8 ticks per bit
    jmp pin, good_stop          ; t0+76 is mid stop bit: must be high
    irq set                     ; framing error: tell the host
    wait 1 pin 1                ; wait for the line to go idle again
    jmp start
good_stop:
    push                        ; ISR -> RX FIFO
    jmp start
