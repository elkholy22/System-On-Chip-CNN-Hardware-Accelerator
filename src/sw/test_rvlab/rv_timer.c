/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <rvlab.h>

int rv_timer_test(void) {
    int readword;
    bool correct;
    int retval = 0;

    // Disable timer:
    REG32(RV_TIMER_CTRL(0)) = (0<<RV_TIMER_CTRL_ACTIVE0_LSB);
    
    REG32(RV_TIMER_TIMER_V_UPPER0(0)) = 0x00000000;
    REG32(RV_TIMER_TIMER_V_LOWER0(0)) = 0x11223344;

    correct = (readword = REG32(RV_TIMER_TIMER_V_LOWER0(0))) == 0x11223344;
    if(!correct)
        retval = 1;
    printf("read back RV_TIMER_TIMER_V_LOWER0: %i (%s)\n", readword, correct?"correct":"WRONG");


    // Try out comparator / interrupt register with zero step:
    REG32(RV_TIMER_CFG0(0)) = (0<<RV_TIMER_CFG0_STEP_LSB) | (0<<RV_TIMER_CFG0_PRESCALE_LSB);
    REG32(RV_TIMER_CTRL(0)) = (1<<RV_TIMER_CTRL_ACTIVE0_LSB);
    REG32(RV_TIMER_COMPARE_UPPER0_0(0)) = 0x00000000;
    REG32(RV_TIMER_INTR_ENABLE0(0)) = (1<<RV_TIMER_INTR_ENABLE0_IE0_LSB);

    REG32(RV_TIMER_COMPARE_LOWER0_0(0)) = 0x10000000;

    // clear interrupt
    REG32(RV_TIMER_INTR_STATE0(0)) = (1<<RV_TIMER_INTR_STATE0_IS0_LSB);

    correct = (readword = REG32(RV_TIMER_INTR_STATE0(0))) == (1<<RV_TIMER_INTR_STATE0_IS0_LSB);
    if(!correct)
        retval = 1;
    printf("read back RV_TIMER_INTR_STATE0: %i (%s)\n", readword, correct?"correct":"WRONG");

    REG32(RV_TIMER_COMPARE_LOWER0_0(0)) = 0x20000000;

    // clear interrupt
    REG32(RV_TIMER_INTR_STATE0(0)) = (1<<RV_TIMER_INTR_STATE0_IS0_LSB);


    correct = (readword = REG32(RV_TIMER_INTR_STATE0(0))) == (0<<RV_TIMER_INTR_STATE0_IS0_LSB);
    if(!correct)
        retval = 1;
    printf("read back RV_TIMER_INTR_STATE0: %i (%s)\n", readword, correct?"correct":"WRONG");

    correct = (readword = REG32(RV_TIMER_TIMER_V_LOWER0(0))) == 0x11223344;
    if(!correct)
        retval = 1;
    printf("read back RV_TIMER_TIMER_V_LOWER0: %i (%s)\n", readword, correct?"correct":"WRONG");

    // Enable step
    REG32(RV_TIMER_CFG0(0)) = (1<<RV_TIMER_CFG0_STEP_LSB) | (0<<RV_TIMER_CFG0_PRESCALE_LSB);

    correct = (readword = REG32(RV_TIMER_TIMER_V_LOWER0(0))) > 0x11223344;
    if(!correct)
        retval = 1;
    printf("read back RV_TIMER_TIMER_V_LOWER0: %i (%s)\n", readword, correct?"correct":"WRONG");

    // Reset rv_timer:
    REG32(RV_TIMER_CFG0(0)) = (RV_TIMER_CFG0_STEP_DEFAULT<<RV_TIMER_CFG0_STEP_LSB)
        | (RV_TIMER_CFG0_PRESCALE_DEFAULT<<RV_TIMER_CFG0_PRESCALE_LSB);
    REG32(RV_TIMER_CTRL(0)) = (RV_TIMER_CTRL_ACTIVE0_DEFAULT<<RV_TIMER_CTRL_ACTIVE0_LSB);

    return retval;
}
