/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 *
 * Mini-Anwendung fuer das Lauflicht ueber die HAL.
 * Demonstriert Register-Lesen/-Schreiben und das Durchschalten der Modi.
 */

#include <stdio.h>
#include <rvlab.h>
#include "student_rlight.h"

static void delay_cycles(uint32_t n) {
    REG32(RV_TIMER_CTRL(0)) = (1 << RV_TIMER_CTRL_ACTIVE0_LSB);
    REG32(RV_TIMER_TIMER_V_LOWER0(0)) = 0;
    while (REG32(RV_TIMER_TIMER_V_LOWER0(0)) < n);
}

int main(void) {
    /* 1) Register schreiben + zuruecklesen */
    rlight_set_pattern(0x18);
    rlight_set_speed(10);
    printf("pattern=0x%02x speed=%u\n", rlight_get_pattern(), rlight_get_speed());

    /* 2) Jeden Modus kurz laufen lassen und die LEDs per Polling beobachten */
    unsigned modes[4] = {
        RLIGHT_MODE_RIGHT, RLIGHT_MODE_LEFT,
        RLIGHT_MODE_PINGPONG, RLIGHT_MODE_STOP
    };

    for (int m = 0; m < 4; m++) {
        rlight_set_mode(modes[m]);
        printf("--- mode %u ---\n", modes[m]);
        for (int k = 0; k < 8; k++) {
            printf("leds=0x%02x\n", rlight_get_status());
            delay_cycles(50);
        }
    }

    /* 3) Muster im Betrieb aendern -> muss sofort sauber umschalten */
    rlight_set_mode(RLIGHT_MODE_PINGPONG);
    rlight_set_pattern(0x81);
    printf("nach Muster-Wechsel: leds=0x%02x\n", rlight_get_status());

    return 0;
}
