#ifndef CYCLES_H
#define CYCLES_H
#include <stdint.h>

static inline void perf_enable(void){
    asm volatile ("csrw 0x320, %0" :: "r"(0));   // mcountinhibit=0 -> Zaehler laufen
}
static inline uint32_t rdcycle(void){
    uint32_t v;
    asm volatile ("csrr %0, 0xB00" : "=r"(v));   // mcycle lesen
    return v;
}
#endif