/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#ifndef _RVLAB_H
#define _RVLAB_H

#define IRQ_TIMER 7
#define IRQ_EXTERNAL 11

#define DDR3_BASE_ADDR ((void *) 0x80000000)
#define DDR3_SIZE      ((size_t) 0x20000000)

int ddr_init(void);

#include <regaccess.h>

#include <reggen/ddr_ctrl.h>
#define DDR_CTRL0_BASE_ADDR 0x1f001000

#include <reggen/regdemo.h>
#define REGDEMO0_BASE_ADDR 0x1f002000

#include <reggen/rv_timer.h>
#define RV_TIMER0_BASE_ADDR 0x1f000000

#include <reggen/student_dma.h>
#define STUDENT_DMA0_BASE_ADDR 0x20000000

// Lauflicht (reggen) -- Geraet 0 am student_tlul_mux
#include <reggen/student_rlight.h>
#define STUDENT_RLIGHT0_BASE_ADDR 0x10000000

// Interrupt-Controller (handgeschrieben, kein reggen) -- Geraet 1 am mux
#define STUDENT_IRQ_CTRL0_BASE_ADDR 0x10100000

// CNN-Accelerator (reggen) -- Geraet 2 am mux
#include <reggen/student_cnn.h>
#define STUDENT_CNN0_BASE_ADDR 0x10200000

// UART (reggen) -- Geraet 3 am mux (RX = Pmod A Pin 0, TX = Pmod A Pin 1)
#include <reggen/student_uart.h>
#define STUDENT_UART0_BASE_ADDR 0x10300000

// Add includes for additional register definition headers
// and define corresponding _BASE_ADDR values here.

#endif // _RVLAB_H
