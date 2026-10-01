/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include <rvlab.h>
#include "dma.h"

void dma_write_desc(volatile dma_descriptor_t *d) {
    REG32(STUDENT_DMA_NOW_DADR(0)) = (uint32_t) d;
}

void dma_wait(void) {
    while(REG32(STUDENT_DMA_STATUS(0)) != 0);
}
