// array_sum_arm64.s — macOS Apple Silicon.
// Sums a 5-element int array through a helper placed BEFORE _main, then prints
// the result. Expected output: "Sum = 150"
//
// Two things make this sample harder than hello_arm64.s:
//   * `_sum_array` sits *before* `_main`, so instruction offsets counted from
//     the top of the file are not offsets from the entry symbol;
//   * formatted output needs `_printf` (a real branch out of the function).
//
// NOTE: on Apple arm64 the variadic arguments of printf live on the STACK, so
// the value is stored into a 16-byte-aligned slot before the call.
    .section __TEXT,__cstring,cstring_literals
fmt:
    .asciz "Sum = %d\n"

    .data
    .p2align 2
numbers:
    .word 10, 20, 30, 40, 50
count:
    .word 5

    .text
    .p2align 2
// int sum_array(const int *base, int n)  — x0 = base, w1 = n  ->  w0 = sum
_sum_array:
    mov     w2, #0                  // sum = 0
    mov     w4, #0                  // i = 0
sum_loop:
    cmp     w4, w1
    b.ge    sum_done
    ldr     w3, [x0, w4, sxtw #2]   // x3 = base[i]
    add     x2, x2, x3              // sum += base[i]
    add     w4, w4, #1              // ++i
    b       sum_loop
sum_done:
    mov     w0, w2
    ret

    .globl _main
    .p2align 2
_main:
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]
    mov     x29, sp

    adrp    x0, numbers@PAGE
    add     x0, x0, numbers@PAGEOFF
    mov     w1, #5
    bl      _sum_array
    mov     w19, w0

    sub     sp, sp, #16
    str     x19, [sp]
    adrp    x0, fmt@PAGE
    add     x0, x0, fmt@PAGEOFF
    bl      _printf
    add     sp, sp, #16

    mov     w0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
