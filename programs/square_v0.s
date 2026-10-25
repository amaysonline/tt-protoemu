; v0 demo: a square wave on pin 0 using only side-set and jumps (8 ticks per period)
.pin 0 pushpull
.side_pin 0
.clkdiv 3
high:
    jmp low    side 1 [3]
low:
    jmp high   side 0 [3]
