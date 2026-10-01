/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#define DMA_OP_MEMSET 0
#define DMA_OP_MEMCPY 1

typedef struct {
  uint32_t operation;
  uint32_t length;
  uint32_t src_adr;
  uint32_t dst_adr;
} dma_descriptor_t;

void dma_write_desc(volatile dma_descriptor_t *d);
void dma_wait(void);
