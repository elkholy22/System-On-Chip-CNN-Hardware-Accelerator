/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <rvlab.h>

int regdemo_test(void) {
    int readword;
    bool correct;
    int retval = 0;

    REG32(REGDEMO_SHIFTIN(0)) = 1234;

    correct = (readword = REG32(REGDEMO_SHIFTIN(0))) == 1234;
    if(!correct)
        retval = 1;
    printf("read back shiftin: %i (%s)\n", readword, correct?"correct":"WRONG");

    REG32(REGDEMO_SHIFTCFG(0)) = (10<<REGDEMO_SHIFTCFG_AMT_LSB) | (0<<REGDEMO_SHIFTCFG_DIR_LSB);

    correct = (readword = REG32(REGDEMO_SHIFTOUT(0))) == 1234 << 10;
    if(!correct)
        retval = 1;
    printf("shifted left by 3: %i (%s)\n", readword, correct?"correct":"WRONG");
    
    REG32(REGDEMO_SHIFTCFG(0)) = (1<<REGDEMO_SHIFTCFG_AMT_LSB) | (1<<REGDEMO_SHIFTCFG_DIR_LSB);
    
    correct = (readword = REG32(REGDEMO_SHIFTOUT(0))) == 1234 >> 1;
    if(!correct)
        retval = 1;
    printf("shifted right by 1: %i (%s)\n", readword, correct?"correct":"WRONG");

    return retval;
}
