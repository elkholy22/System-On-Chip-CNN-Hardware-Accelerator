#ifndef _STUDENT_CNN_HAL_H
#define _STUDENT_CNN_HAL_H

#include <stdint.h>

#define STUDENT_CNN_CTRL_START_BIT  0
#define STUDENT_CNN_CTRL_CLEAR_BIT  1
#define STUDENT_CNN_STATUS_BUSY_BIT 0
#define STUDENT_CNN_STATUS_DONE_BIT 1

#define CNN_IMG_PIXELS 784   /* 28 x 28 */

/* Bild laden (784 int8-Pixel, quantisiert wie in PyTorch/image.mem). */
void cnn_write_image(const uint8_t *img);

/* Inferenz starten (nicht blockierend). */
void cnn_start(void);

/* 1 wenn done gesetzt ist. */
int cnn_done(void);

/* Blockierend: starten, auf done warten, Ziffer (0..9) zurueckgeben. */
unsigned cnn_infer(const uint8_t *img);

/* Zyklen der letzten Inferenz (gueltig wenn done). */
uint32_t cnn_cycles(void);

#endif /* _STUDENT_CNN_HAL_H */
