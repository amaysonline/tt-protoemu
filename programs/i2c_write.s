; I2C controller, write transaction, standard mode (100 kHz), with clock stretching.
; SDA = pin 6, SCL = pin 7, both open-drain (board needs pull-up resistors).
; Host pushes into the TX FIFO: N, (address << 1) | 0, then N data bytes.
; N = 0 sends just the address: handy for scanning the bus.
; NACK raises IRQ and ends the transfer with a STOP.
.pin 6 opendrain
.pin 7 opendrain
.side_pin 7
.set_base 6
.set_count 1
.out_base 6
.in_base 6
.jmp_pin 6
.out_shift msb
.clkdiv 62                  ; 50 MHz / 63 = 794 kHz ticks, 8 per bit -> 99.2 kHz
init:
    set pins, 1     side 1      ; release SDA and SCL
idle:
    pull                        ; N = number of data bytes
    out y, 8
    pull                        ; address byte
    wait 1 pin 7                ; make sure SCL is high (bus idle)
    set pins, 0            [3]  ; START: SDA falls while SCL is high
byte:
    set x, 7        side 0 [1]  ; SCL low; 8 bits to send
bitloop:
    out pins, 1            [2]  ; SDA = next bit while SCL is low
    nop             side 1      ; release SCL
    wait 1 pin 7           [2]  ; clock stretching: wait until SCL really is high
    jmp x--, bitloop side 0     ; SCL low again
    set pins, 1            [2]  ; release SDA so the target can ACK
    nop             side 1
    wait 1 pin 7           [1]
    jmp pin, nack               ; SDA still high -> no ACK
    jmp y--, next   side 0      ; more bytes to send?
stop:
    set pins, 0            [3]  ; SDA low while SCL is low
    nop             side 1      ; release SCL
    wait 1 pin 7           [3]
    set pins, 1            [7]  ; STOP: SDA rises while SCL is high
    jmp idle
next:
    pull
    jmp byte
nack:
    irq set         side 0
    jmp stop
