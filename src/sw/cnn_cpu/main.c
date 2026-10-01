#include <stdint.h>
#include "rvlab.h"
#include "cycles.h"
#include "cnn_sw.h"
#include "image7.h"        


#include <stdio.h>
#define PRINTF(...) printf(__VA_ARGS__)

int main(void){
    perf_enable();

    uint32_t lc[6];
    uint32_t t0 = rdcycle();
    int digit  = cnn_sw_infer_timed(image7, lc);
    uint32_t t1 = rdcycle();
    uint32_t total = t1 - t0;

    PRINTF("CNN (CPU/SW) -> Ziffer = %d\n", digit);
    PRINTF("Total       : %u Takte\n", (unsigned)total);
    PRINTF("  conv1: %u  pool1: %u  conv2: %u\n",
           (unsigned)lc[0],(unsigned)lc[1],(unsigned)lc[2]);
    PRINTF("  pool2: %u  fc1: %u  fc2+arg: %u\n",
           (unsigned)lc[3],(unsigned)lc[4],(unsigned)lc[5]);
    PRINTF(digit==IMAGE7_LABEL ? "RESULT: PASS\n" : "RESULT: FAIL\n");

    return 0;   // sauberer Exit -> crt0/hostio beendet den Lauf (wie cnn/main.c)
}