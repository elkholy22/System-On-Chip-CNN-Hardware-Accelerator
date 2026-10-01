#include <rvlab.h>
#include "student_cnn.h"

void cnn_write_image(const uint8_t *img) {
    /* Schreibzeiger auf 0 (wichtig fuer jede weitere Inferenz) */
    REG32(STUDENT_CNN_CTRL(0)) = (1u << STUDENT_CNN_CTRL_CLEAR_BIT);
    for (int i = 0; i < CNN_IMG_PIXELS; i++) {
        REG32(STUDENT_CNN_PIXEL(0)) = (uint32_t) img[i];
    }
}

void cnn_start(void) {
    REG32(STUDENT_CNN_CTRL(0)) = (1u << STUDENT_CNN_CTRL_START_BIT);
}

int cnn_done(void) {
    return (REG32(STUDENT_CNN_STATUS(0)) & (1u << STUDENT_CNN_STATUS_DONE_BIT)) != 0;
}

unsigned cnn_infer(const uint8_t *img) {
    cnn_write_image(img);
    cnn_start();
    while (!cnn_done());
    return REG32(STUDENT_CNN_RESULT(0)) & 0xF;
}

uint32_t cnn_cycles(void) {
    return REG32(STUDENT_CNN_CYCLE_COUNT(0));
}
