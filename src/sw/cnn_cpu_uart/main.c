/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 *
 * CPU/SW-Gegenstueck zu cnn_uart: identisches UART-Protokoll, aber die
 * Inferenz laeuft in Software auf dem CV32E40P (cnn_sw.c) statt auf dem
 * Beschleuniger. So kann DASSELBE pytorch/send_image.py Bilder schicken und
 * du vergleichst CPU vs. HW auf exakt demselben Live-Input.
 *
 * Protokoll (wie cnn_uart, damit send_image.py unveraendert funktioniert):
 *   PC -> FPGA : 784 Bytes (quantisierte uint8-Pixel, wie image.mem)
 *   FPGA -> PC : eine Zeile mit GENAU einer Ziffer + "\r\n" (via student_uart)
 * Die Pro-Layer-Zyklen (mcycle) gehen ueber printf/hostio an die Flow-Konsole,
 * NICHT ueber den student_uart -> stoeren den Parser von send_image.py nicht.
 */

#include <stdio.h>
#include <rvlab.h>

/* SW-Inferenz aus cnn_cpu mitkompilieren (Build nimmt nur .c aus DIESEM Ordner).
 * Der textuelle Include zieht cnn_sw.c + dessen cnn_params.h/cycles.h/cnn_sw.h
 * (quote-includes werden relativ zu cnn_sw.c, also aus ../cnn_cpu/, aufgeloest). */
#include "../cnn_cpu/cnn_sw.c"
#include "../cnn_cpu/cnn_sw.h"
#include "../cnn_cpu/cycles.h"
#include "../cnn_uart/student_uart_hal.h"

#define UART_CLK_HZ 50000000u
#define UART_BAUD   115200u
#define UART_BAUD_DIV ((uint16_t)(UART_CLK_HZ / UART_BAUD - 1u))

#define CNN_IMG_PIXELS 784

/* rlight LED-Peripherie @ 0x10000000: erkannte Ziffer binaer auf den 8 LEDs. */
#define RLIGHT_BASE      0x10000000u
#define RLIGHT_PATTERN   (*(volatile uint32_t *)(RLIGHT_BASE + 0x0u))
#define RLIGHT_MODE      (*(volatile uint32_t *)(RLIGHT_BASE + 0x4u))
#define RLIGHT_MODE_STOP 3u

static uint32_t reverse_8bits(uint32_t val) {
    uint32_t rev = 0;
    for (int i = 0; i < 8; i++) {
        rev = (rev << 1) | (val & 1u);
        val >>= 1;
    }
    return rev;
}

int main(void) {
    printf("CNN (CPU/SW) + UART Demo @ UART 0x%08x\n",
           (unsigned) STUDENT_UART0_BASE_ADDR);

    perf_enable();                     /* mcycle laufen lassen (einmalig) */

    RLIGHT_MODE = RLIGHT_MODE_STOP;    /* LEDs statisch -> zeigen die Ziffer */
    RLIGHT_PATTERN = 0;

    uart_init(UART_BAUD_DIV);
    uart_puts("CNN ready\r\n");
    printf("UART-Server (CPU/SW) laeuft (baud_div=%u). Warte auf 784-Byte-Bilder...\n",
           (unsigned) UART_BAUD_DIV);

    static uint8_t img[CNN_IMG_PIXELS];
    uint32_t lc[6];

    for (;;) {
        for (int i = 0; i < CNN_IMG_PIXELS; i++) {
            img[i] = uart_getc();
        }

        uint32_t t0 = rdcycle();
        int digit  = cnn_sw_infer_timed(img, lc);
        uint32_t t1 = rdcycle();
        uint32_t total = t1 - t0;

        RLIGHT_PATTERN = reverse_8bits((uint32_t) digit);

        /* Antwort an send_image.py: GENAU eine Ziffer + CRLF ueber student_uart */
        uart_putc((char) ('0' + digit));
        uart_puts("\r\n");

        /* Zyklen ueber hostio (nicht ueber student_uart) -> Parser bleibt sauber */
        printf("UART-Inferenz (CPU/SW): Ziffer = %d  [%u Takte]\n",
               digit, (unsigned) total);
        printf("  conv1=%u pool1=%u conv2=%u pool2=%u fc1=%u fc2+arg=%u\n",
               (unsigned) lc[0], (unsigned) lc[1], (unsigned) lc[2],
               (unsigned) lc[3], (unsigned) lc[4], (unsigned) lc[5]);
    }

    return 0;
}
