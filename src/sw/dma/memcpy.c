/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include "rvlab.h"
#include "dma.h"

/* Reine Software-Implementierung: wortweises Kopieren.
 * length ist ein Vielfaches von 4 (32-bit-Zugriffe, wie die HW). */
void memcpy_soft(void *dest, void *src, uint32_t length) {
    uint32_t *d = (uint32_t *) dest;
    uint32_t *s = (uint32_t *) src;
    for (uint32_t i = 0; i < length / sizeof(uint32_t); i++) {
        d[i] = s[i];
    }
}

/* Hardware-Implementierung: Deskriptor aufsetzen und den DMA-Host starten.
 * student_dma liest den Deskriptor selbst aus dem Speicher und kopiert
 * mit gleichzeitigen Read-/Write-Transaktionen (FIFO). */
void memcpy_dma(void *dest, void *src, uint32_t length) {
    volatile dma_descriptor_t d;

    d.operation = DMA_OP_MEMCPY;
    d.length    = length;
    d.src_adr   = (uint32_t) src;
    d.dst_adr   = (uint32_t) dest;

    dma_write_desc(&d);   /* schreibt NOW_DADR -> startet die Operation */
    dma_wait();           /* pollt STATUS, bis wieder idle */
}
