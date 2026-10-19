// arm64_demo.s — macOS Apple Silicon.
// A slightly richer ARM64 sample for the Borland IDE debugger: a loop, a real
// function call (good for Step Into / Step Out) and formatted output.
    .section __TEXT,__cstring,cstring_literals
title:
    .asciz "ARM64 demo — Borland Classic Code Editor"
sum_fmt:
    .asciz "sum(1..10) = %d\n"
add_fmt:
    .asciz "add_three(7, 11, 100) = %d\n"

    .text
    .globl _main
    .p2align 2
_main:
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]
    mov     x29, sp

    adrp    x0, title@PAGE
    add     x0, x0, title@PAGEOFF
    bl      _puts

    // x19 = sum of 1..10
    mov     x19, #0             // accumulator
    mov     x20, #1             // counter
loop:
    add     x19, x19, x20       // x19 += x20
    add     x20, x20, #1        // ++x20
    cmp     x20, #11
    b.lt    loop

    adrp    x0, sum_fmt@PAGE
    add     x0, x0, sum_fmt@PAGEOFF
    mov     x1, x19
    bl      _printf

    // w0 = add_three(7, 11, 100)
    mov     w0, #7
    mov     w1, #11
    mov     w2, #100
    bl      _add_three
    mov     w19, w0

    adrp    x0, add_fmt@PAGE
    add     x0, x0, add_fmt@PAGEOFF
    mov     w1, w19
    bl      _printf

    mov     w0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// int add_three(int a, int b, int c) — w0 = a + b + c
    .globl _add_three
    .p2align 2
_add_three:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    add     w0, w0, w1
    add     w0, w0, w2
    ldp     x29, x30, [sp], #16
    ret
