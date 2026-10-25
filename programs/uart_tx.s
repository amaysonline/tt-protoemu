; UART transmitter, 8N1, LSB first. TX = pin 0. 8 ticks per bit.
.pin 0 pushpull
.side_pin 0
.out_base 0
.out_shift lsb
.clkdiv 53                  ; 50 MHz / (8 x 115200) = 54.25 -> divide by 54
start:
    pull            side 1 [7]  ; line idle/stop bit high; waits for a byte
    set x, 7        side 0 [7]  ; start bit low (8 ticks); x counts 8 data bits
bitloop:
    out pins, 1                 ; next data bit onto TX
    jmp x--, bitloop       [6]  ; 1 + 7 = 8 ticks per bit
    jmp start       side 1      ; begin stop bit (pull adds 8 more ticks)
