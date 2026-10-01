/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 *
 * Verwendet die von reggen generierten Adress-Makros aus
 * <reggen/student_rlight.h> (entsteht durch `flow reggen.generate`).
 * Die Basisadresse STUDENT_RLIGHT0_BASE_ADDR ist in rvlab.h definiert.
 */

#include <rvlab.h>
#include "student_rlight.h"

void rlight_set_pattern(uint8_t pattern) {
    REG32(STUDENT_RLIGHT_PATTERN(0)) = pattern;
}

uint8_t rlight_get_pattern(void) {
    return (uint8_t) (REG32(STUDENT_RLIGHT_PATTERN(0)) & 0xFF);
}

void rlight_set_mode(unsigned mode) {
    REG32(STUDENT_RLIGHT_MODE(0)) = mode & 0x3;
}

unsigned rlight_get_mode(void) {
    return REG32(STUDENT_RLIGHT_MODE(0)) & 0x3;
}

void rlight_set_speed(uint32_t n) {
    REG32(STUDENT_RLIGHT_SPEED(0)) = n;
}

uint32_t rlight_get_speed(void) {
    return REG32(STUDENT_RLIGHT_SPEED(0));
}

uint8_t rlight_get_status(void) {
    return (uint8_t) (REG32(STUDENT_RLIGHT_STATUS(0)) & 0xFF);
}
