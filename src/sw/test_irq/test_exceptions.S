// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2024 RVLab Contributors

.globl test_illegal_instruction
test_illegal_instruction:
    .word 0x10b5f453
    ret

.globl test_ecall
test_ecall:
    ecall
    ret

.globl test_instruction_access_fault
test_instruction_access_fault:
    li t0, 0x40000000
    jr t0
    ret
