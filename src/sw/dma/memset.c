/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include "rvlab.h"
#include "dma.h"

void memset_soft(void *ptr, uint32_t value, uint32_t length) {
    int * ptr_i = (int*) ptr;
    for (int i = 0; i < (length/sizeof(int)); i++) {
        ptr_i[i] = value;
    }
}

void memset_dma(void *ptr, uint32_t value, uint32_t length) {
    volatile dma_descriptor_t d;
    
    d.operation = DMA_OP_MEMSET;
    d.dst_adr   = (uint32_t) ptr;
    d.src_adr   = value;
    d.length    = length;
    
    dma_write_desc(&d);
    dma_wait();
}
