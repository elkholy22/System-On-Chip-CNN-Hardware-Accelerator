/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 *
 * HAL fuer das Lauflicht (student_rlight).
 * Kapselt alle Registerzugriffe; die Anwendung sieht nur diese Funktionen.
 */

#ifndef _STUDENT_RLIGHT_H
#define _STUDENT_RLIGHT_H

#include <stdint.h>

#define RLIGHT_MODE_RIGHT    0
#define RLIGHT_MODE_LEFT     1
#define RLIGHT_MODE_PINGPONG 2
#define RLIGHT_MODE_STOP     3

void     rlight_set_pattern(uint8_t pattern);
uint8_t  rlight_get_pattern(void);

void     rlight_set_mode(unsigned mode);   /* RLIGHT_MODE_* */
unsigned rlight_get_mode(void);

void     rlight_set_speed(uint32_t n);     /* Pause in Taktzyklen pro Schritt */
uint32_t rlight_get_speed(void);

uint8_t  rlight_get_status(void);          /* aktuell leuchtende LEDs */

#endif /* _STUDENT_RLIGHT_H */
