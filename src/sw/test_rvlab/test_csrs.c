/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include <stdio.h>
#include <stdbool.h>
#include <rvlab.h>

int test_csrs(void) {
    int retval = 0;

    int mcycle_start, mcycle_end, mcycle_passed;
    int minstret_start, minstret_end, minstret_passed;

    mcycle_start = read_csr("mcycle");
    minstret_start = read_csr("minstret");
    printf("mcycle_start: 0x%08x\n", mcycle_start);
    
    mcycle_end = read_csr("mcycle");
    minstret_end = read_csr("minstret");
    printf("mcycle_end: 0x%08x\n", mcycle_end);

    mcycle_passed = mcycle_end -mcycle_start;
    minstret_passed = minstret_end - minstret_start;
    printf("mcycles passed: %i\tminstret passed: %i\n", mcycle_passed, minstret_passed);

    if(mcycle_passed > 10000 || mcycle_passed < 0) {
        printf("ERROR: Unexpected number of passed mcycles.\n");
        retval = 1;
    }

    return retval;
}
