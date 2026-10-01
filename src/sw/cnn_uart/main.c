/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include <stdio.h>
#include <rvlab.h>
/* CNN-HAL aus sw/cnn mitkompilieren (Build nimmt nur .c aus DIESEM Ordner) */
#include "../cnn/student_cnn.c"
#include "../cnn/image7.h"
#include "student_uart_hal.h"
#include "student_oled_hal.h"

#define UART_CLK_HZ 50000000u
#define UART_BAUD   115200u
#define UART_BAUD_DIV ((uint16_t)(UART_CLK_HZ / UART_BAUD - 1u))

/* rlight LED-Peripherie @ 0x10000000: klassifizierte Ziffer binaer auf den 8
 * LEDs anzeigen. mode=STOP haelt das Muster statisch (kein Lauflicht). */
#define RLIGHT_BASE      0x10000000u
#define RLIGHT_PATTERN   (*(volatile uint32_t *)(RLIGHT_BASE + 0x0u))
#define RLIGHT_MODE      (*(volatile uint32_t *)(RLIGHT_BASE + 0x4u))
#define RLIGHT_MODE_STOP 3u

/* Dreht die untersten 8 Bits um (MSB <-> LSB Reversal for LED bit ordering) */
static uint32_t reverse_8bits(uint32_t val) {
    uint32_t rev = 0;
    for (int i = 0; i < 8; i++) {
        rev = (rev << 1) | (val & 1u);
        val >>= 1;
    }
    return rev;
}

int main(void) {
    printf("CNN+UART Demo @ 0x%08x / 0x%08x\n",
           (unsigned) STUDENT_CNN0_BASE_ADDR, (unsigned) STUDENT_UART0_BASE_ADDR);

    /* Staleness-Guard: Build-Kennung ausgeben. Erwartet 0xC10000NN (NN=Opt-Stufe).
     * Stimmt der Wert -> frisch synthetisierter (nicht-stale) Build. */
    printf("CNN build version = 0x%08x (expect 0xC10000xx)\n",
           (unsigned) REG32(STUDENT_CNN_VERSION(0)));

    RLIGHT_MODE = RLIGHT_MODE_STOP;    /* LEDs statisch -> zeigen die Ziffer */
    RLIGHT_PATTERN = 0;                /* LEDs initial ausschalten */

    oled_init();                       /* OLED hochfahren (SSD1306 128x32) */
    oled_fill(0x00);                   /* <-- OLED anfangs komplett leeren (black) */

    /* ---------------------------------------------------------------------
     * 1) Selbsttest DEAKTIVIERT:
     * Die Inferenz von `image7` auf dem Bootup wurde entfernt.
     * --------------------------------------------------------------------- */

    /* 2) UART-Server: Bilder vom PC empfangen und klassifizieren */
    uart_init(UART_BAUD_DIV);
    uart_puts("CNN ready\r\n");
    printf("UART-Server laeuft (baud_div=%u). Warte auf 784-Byte-Bilder...\n",
           (unsigned) UART_BAUD_DIV);

    static uint8_t img[CNN_IMG_PIXELS];
    unsigned digit;

    for (;;) {
        for (int i = 0; i < CNN_IMG_PIXELS; i++) {
            img[i] = uart_getc();
        }
        digit = cnn_infer(img);

        /* Ziffer spiegeln, damit LEDs von LSB nach MSB (oder umgekehrt) leuchten */
        RLIGHT_PATTERN = reverse_8bits(digit);

        oled_show_digit(digit);            /* erkannte Ziffer gross auf dem OLED */
        uart_putc((char) ('0' + digit));
        uart_puts("\r\n");

        /* Per-Schicht-Zyklen (DEBUG): kumulative Snapshots -> Differenzen */
        unsigned tot = (unsigned) cnn_cycles();
        unsigned l0  = REG32(STUDENT_CNN_CYCLE_LAYER0(0));
        unsigned l1  = REG32(STUDENT_CNN_CYCLE_LAYER1(0));
        unsigned l2  = REG32(STUDENT_CNN_CYCLE_LAYER2(0));
        unsigned l3  = REG32(STUDENT_CNN_CYCLE_LAYER3(0));
        printf("UART-Inferenz: Ziffer = %u  [%u Takte]\n", digit, tot);
        printf("  conv1=%u conv2=%u fc1=%u fc2=%u argmax=%u\n",
               l0, l1 - l0, l2 - l1, l3 - l2, tot - l3);
    }

    return 0;
}
