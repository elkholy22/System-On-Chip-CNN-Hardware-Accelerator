#ifndef CNN_SW_H
#define CNN_SW_H
#include <stdint.h>
// img = 784 quantisierte Pixel (uint8-Codes, 28x28 row-major) = dieselben wie fuer die HW
int cnn_sw_infer(const uint8_t *img);
// lc[0]=conv1 [1]=pool1 [2]=conv2 [3]=pool2 [4]=fc1 [5]=fc2+argmax
int cnn_sw_infer_timed(const uint8_t *img, uint32_t lc[6]);
#endif