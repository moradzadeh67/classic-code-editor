// hello_arm64.s - macOS Apple Silicon. Sums 1..5 into x19, prints a message.
    .section __TEXT,__cstring,cstring_literals
msg:
    .asciz "Hello from ARM64 assembly"

    .text
    .globl _main
    .p2align 2
_main:
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]
    mov     x29, sp
    mov     x19, #0
    mov     x20, #1
loop:
    add     x19, x19, x20
    add     x20, x20, #1
    cmp     x20, #6
    b.lt    loop
    adrp    x0, msg@PAGE
    add     x0, x0, msg@PAGEOFF
    bl      _puts
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
