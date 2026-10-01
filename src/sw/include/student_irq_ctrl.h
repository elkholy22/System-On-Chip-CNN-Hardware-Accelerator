/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 *
 * HAL fuer den sekundaeren Interrupt-Controller (student_irq_ctrl).
 * Header-only: zeitkritische Zugriffe sind static inline (Ex5-Vorgabe).
 *
 * Hinweis: Die Sprungtabelle ist hier static -> in EINER Compilation-Unit
 * (z.B. deiner main.c) verwenden. Basisadresse STUDENT_IRQ_CTRL0_BASE_ADDR
 * kommt aus rvlab.h.
 */

#ifndef _STUDENT_IRQ_CTRL_H
#define _STUDENT_IRQ_CTRL_H

#include <stdint.h>
#include <regaccess.h>
#include <rvlab.h>

#define IRQ_CTRL_MAX 32

#define IRQ_CTRL_ALL_EN    (STUDENT_IRQ_CTRL0_BASE_ADDR + 0x00)
#define IRQ_CTRL_MASK      (STUDENT_IRQ_CTRL0_BASE_ADDR + 0x04)
#define IRQ_CTRL_MASK_SET  (STUDENT_IRQ_CTRL0_BASE_ADDR + 0x08)
#define IRQ_CTRL_MASK_CLR  (STUDENT_IRQ_CTRL0_BASE_ADDR + 0x0C)
#define IRQ_CTRL_STATUS    (STUDENT_IRQ_CTRL0_BASE_ADDR + 0x10)
#define IRQ_CTRL_IRQ_NO    (STUDENT_IRQ_CTRL0_BASE_ADDR + 0x14)
#define IRQ_CTRL_TEST      (STUDENT_IRQ_CTRL0_BASE_ADDR + 0x18)
#define IRQ_CTRL_TEST_IRQ  (STUDENT_IRQ_CTRL0_BASE_ADDR + 0x1C)

/* --- Register-Zugriffe (inline, da oft im Interrupt-Handler benutzt) --- */
static inline void     irq_ctrl_set_all_en(int en)      { REG32(IRQ_CTRL_ALL_EN) = en ? 1 : 0; }
static inline uint32_t irq_ctrl_get_mask(void)          { return REG32(IRQ_CTRL_MASK); }
static inline void     irq_ctrl_set_mask(uint32_t m)    { REG32(IRQ_CTRL_MASK) = m; }
static inline void     irq_ctrl_mask_set(uint32_t bits) { REG32(IRQ_CTRL_MASK_SET) = bits; }
static inline void     irq_ctrl_mask_clr(uint32_t bits) { REG32(IRQ_CTRL_MASK_CLR) = bits; }
static inline uint32_t irq_ctrl_get_status(void)        { return REG32(IRQ_CTRL_STATUS); }
static inline uint32_t irq_ctrl_get_irq_no(void)        { return REG32(IRQ_CTRL_IRQ_NO); }
static inline void     irq_ctrl_set_test(int t)         { REG32(IRQ_CTRL_TEST) = t ? 1 : 0; }
static inline void     irq_ctrl_set_test_irq(uint32_t v){ REG32(IRQ_CTRL_TEST_IRQ) = v; }

/* --- Sprungtabelle (Array von Funktionszeigern) --- */
typedef void (*irq_handler_fn)(void);

static void irq_ctrl_dummy_handler(void) { /* nichts */ }

static irq_handler_fn irq_ctrl_table[IRQ_CTRL_MAX] = {
    [0 ... IRQ_CTRL_MAX - 1] = irq_ctrl_dummy_handler   /* GCC range-init */
};

static inline void student_irq_ctrl_set(unsigned n, irq_handler_fn fn) {
    if (n < IRQ_CTRL_MAX) irq_ctrl_table[n] = fn ? fn : irq_ctrl_dummy_handler;
}

static inline irq_handler_fn student_irq_ctrl_get(unsigned n) {
    return (n < IRQ_CTRL_MAX) ? irq_ctrl_table[n] : irq_ctrl_dummy_handler;
}

/* Top-Handler: solange ein unmaskierter IRQ ansteht, den passenden
 * Sub-Handler aus der Tabelle aufrufen. Jeder Sub-Handler MUSS seine
 * Quelle loeschen, sonst Endlosschleife. */
static inline void student_irq_ctrl_top_handler(void) {
    unsigned n;
    while ((n = irq_ctrl_get_irq_no()) < IRQ_CTRL_MAX) {
        irq_ctrl_table[n]();
    }
}

#endif /* _STUDENT_IRQ_CTRL_H */
