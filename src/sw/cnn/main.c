#include <stdio.h>
#include <rvlab.h>
#include "student_cnn.h"
#include "image7.h"

int main(void) {
    printf("CNN-Beschleuniger @ 0x%08x\n", (unsigned) STUDENT_CNN0_BASE_ADDR);

    for (int run = 0; run < 2; run++) {
        unsigned digit = cnn_infer(image7);
        printf("Inferenz %d: erkannte Ziffer = %u (erwartet %u) -> %s  [%u Takte]\n",
               run + 1, digit, IMAGE7_LABEL,
               (digit == IMAGE7_LABEL) ? "PASS" : "FAIL",
               (unsigned) cnn_cycles());
    }

    return 0;
}
