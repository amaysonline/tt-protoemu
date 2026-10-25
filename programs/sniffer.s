; v1.1 logic-analyser mode: log every change on the watched pins as two bytes,
; (ticks since the previous change, new pin state). Needs WAIT CHANGE and MOV from TIME.
.watch_mask 0xC0            ; watch SDA and SCL (pins 6, 7)
.in_base 0
.clkdiv 49                  ; 1 tick = 1 us at 50 MHz
    wait change                 ; first edge: take a snapshot
    mov x, time                 ; clear the timer
loop:
    mov isr, pins
    push                        ; byte 1: pin state after the change
    wait change
    mov isr, time               ; byte 2: ticks since the last change (max 255)
    push
    jmp loop
