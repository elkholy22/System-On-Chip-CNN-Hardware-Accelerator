#include <stdio.h>
#include <rvlab.h>
#include <student_irq_ctrl.h>

#include "../cnn/student_cnn.c"
#include "../cnn/image7.h"

#define CNN_IRQ_SRC_BIT   2u

#define STUDENT_OLED0_BASE_ADDR 0x10400000u
#define OLED_GPIO_REG       (STUDENT_OLED0_BASE_ADDR + 0x0u)
#define OLED_GPIO_MASK      0x3Fu
#define OLED_GPIO_RESETVAL  0x32u

#define RLIGHT_MODE_STOP  3u

#define UART_CLK_HZ   50000000u
#define UART_BAUD     115200u
#define UART_BAUD_DIV ((uint32_t)(UART_CLK_HZ / UART_BAUD - 1u))

#define CNN_DONE_TIMEOUT 200000u
#define UART_TX_TIMEOUT  100000u
#define IRQ_SYNC_TIMEOUT  10000u

static unsigned n_pass, n_fail;

static void check_eq(const char *name, uint32_t got, uint32_t exp) {
    if (got == exp) {
        n_pass++;
        printf("PASS %s\n", name);
    } else {
        n_fail++;
        printf("FAIL %s: expected 0x%x got 0x%x\n", name, (unsigned) exp,
               (unsigned) got);
    }
}

static void check_cond(const char *name, int cond, uint32_t exp, uint32_t got) {
    check_eq(name, cond ? exp : got, exp);
}

static int wait_reg_bits(uintptr_t addr, uint32_t mask, uint32_t want,
                         uint32_t timeout) {
    while (timeout--) {
        if ((REG32(addr) & mask) == want) return 1;
    }
    return 0;
}

static int cnn_wait_done(void) {
    return wait_reg_bits(STUDENT_CNN_STATUS(0),
                         1u << STUDENT_CNN_STATUS_DONE_LSB,
                         1u << STUDENT_CNN_STATUS_DONE_LSB,
                         CNN_DONE_TIMEOUT);
}

static void test_cnn(void) {
    printf("-- CNN @ 0x%08x --\n", (unsigned) STUDENT_CNN0_BASE_ADDR);

    uint32_t ver = REG32(STUDENT_CNN_VERSION(0));
    printf("CNN version = 0x%08x\n", (unsigned) ver);
    check_eq("cnn_version_tag", ver & 0xFFFFFF00u, 0xC1000000u);

    uint32_t st = REG32(STUDENT_CNN_STATUS(0));
    printf("CNN status = 0x%x (busy=%u done=%u)\n", (unsigned) st,
           (unsigned) ((st >> STUDENT_CNN_STATUS_BUSY_LSB) & 1u),
           (unsigned) ((st >> STUDENT_CNN_STATUS_DONE_LSB) & 1u));
    check_eq("cnn_status_idle", (st >> STUDENT_CNN_STATUS_BUSY_LSB) & 1u, 0u);

    cnn_write_image(image7);
    cnn_start();
    check_cond("cnn_done_1", cnn_wait_done(), 1u, 0u);

    uint32_t digit1 = REG32(STUDENT_CNN_RESULT(0)) & STUDENT_CNN_RESULT_MASK;
    check_eq("cnn_digit_1", digit1, IMAGE7_LABEL);

    uint32_t tot1 = cnn_cycles();
    check_cond("cnn_cycles_nonzero", tot1 > 0u, 1u, 0u);

    uint32_t l0 = REG32(STUDENT_CNN_CYCLE_LAYER0(0));
    uint32_t l1 = REG32(STUDENT_CNN_CYCLE_LAYER1(0));
    uint32_t l2 = REG32(STUDENT_CNN_CYCLE_LAYER2(0));
    uint32_t l3 = REG32(STUDENT_CNN_CYCLE_LAYER3(0));
    printf("CNN cycles: total=%u l0=%u l1=%u l2=%u l3=%u\n",
           (unsigned) tot1, (unsigned) l0, (unsigned) l1, (unsigned) l2,
           (unsigned) l3);
    check_cond("cnn_layers_monotonic",
               (l0 > 0u) && (l0 < l1) && (l1 < l2) && (l2 < l3) && (l3 < tot1),
               1u, 0u);

    uint32_t conv1 = l0, conv2 = l1 - l0, fc1 = l2 - l1, fc2 = l3 - l2;
    uint32_t argmax = tot1 - l3;
    printf("CNN per-layer: conv1=%u conv2=%u fc1=%u fc2=%u argmax=%u\n",
           (unsigned) conv1, (unsigned) conv2, (unsigned) fc1, (unsigned) fc2,
           (unsigned) argmax);
    check_eq("cnn_layer_sum", conv1 + conv2 + fc1 + fc2, tot1 - argmax);

    cnn_write_image(image7);
    cnn_start();
    check_cond("cnn_done_2", cnn_wait_done(), 1u, 0u);
    uint32_t digit2 = REG32(STUDENT_CNN_RESULT(0)) & STUDENT_CNN_RESULT_MASK;
    uint32_t tot2   = cnn_cycles();
    check_eq("cnn_digit_deterministic", digit2, digit1);
    check_eq("cnn_cycles_deterministic", tot2, tot1);
    check_eq("cnn_layer3_deterministic", REG32(STUDENT_CNN_CYCLE_LAYER3(0)), l3);
}

static void test_rlight(void) {
    printf("-- RLIGHT @ 0x%08x --\n", (unsigned) STUDENT_RLIGHT0_BASE_ADDR);

    uint32_t pat0  = REG32(STUDENT_RLIGHT_PATTERN(0)) & 0xFFu;
    uint32_t mode0 = REG32(STUDENT_RLIGHT_MODE(0)) & 0x3u;

    REG32(STUDENT_RLIGHT_MODE(0)) = RLIGHT_MODE_STOP;
    check_eq("rlight_mode_stop", REG32(STUDENT_RLIGHT_MODE(0)) & 0x3u,
             RLIGHT_MODE_STOP);

    REG32(STUDENT_RLIGHT_PATTERN(0)) = 0xA5u;
    check_eq("rlight_pattern_a5", REG32(STUDENT_RLIGHT_PATTERN(0)) & 0xFFu,
             0xA5u);

    check_eq("rlight_status_a5", REG32(STUDENT_RLIGHT_STATUS(0)) & 0xFFu,
             0xA5u);

    REG32(STUDENT_RLIGHT_PATTERN(0)) = 0x5Au;
    check_eq("rlight_pattern_5a", REG32(STUDENT_RLIGHT_PATTERN(0)) & 0xFFu,
             0x5Au);

    REG32(STUDENT_RLIGHT_PATTERN(0)) = pat0;
    REG32(STUDENT_RLIGHT_MODE(0))    = mode0;
    check_eq("rlight_restored", REG32(STUDENT_RLIGHT_PATTERN(0)) & 0xFFu, pat0);
}

static void test_oled(void) {
    printf("-- OLED GPIO @ 0x%08x --\n", (unsigned) STUDENT_OLED0_BASE_ADDR);

    static const char *pin[6] = { "sdin", "sclk", "dc", "res", "vbat", "vdd" };
    char name[32];

    printf("OLED gpio initial = 0x%02x (reset value 0x%02x)\n",
           (unsigned) REG32(OLED_GPIO_REG), (unsigned) OLED_GPIO_RESETVAL);

    for (int i = 0; i < 6; i++) {
        REG32(OLED_GPIO_REG) = (1u << i);
        sprintf(name, "oled_pin_%s", pin[i]);
        check_eq(name, REG32(OLED_GPIO_REG), (uint32_t)(1u << i));
    }

    REG32(OLED_GPIO_REG) = 0xFFFFFFFFu;
    check_eq("oled_bitmask_5_0", REG32(OLED_GPIO_REG), OLED_GPIO_MASK);
    REG32(OLED_GPIO_REG) = 0x0u;
    check_eq("oled_all_zero", REG32(OLED_GPIO_REG), 0x0u);

    REG32(OLED_GPIO_REG) = OLED_GPIO_RESETVAL;
    check_eq("oled_restored", REG32(OLED_GPIO_REG), OLED_GPIO_RESETVAL);
}

static void test_uart(void) {
    printf("-- UART @ 0x%08x --\n", (unsigned) STUDENT_UART0_BASE_ADDR);

    REG32(STUDENT_UART_CTRL(0)) = 0u;
    uint32_t st = REG32(STUDENT_UART_STATUS(0));
    check_eq("uart_status_idle",
             st & ((1u << STUDENT_UART_STATUS_TX_BUSY_LSB) |
                   (1u << STUDENT_UART_STATUS_RX_VALID_LSB)), 0u);

    uint32_t ctrl = (UART_BAUD_DIV << STUDENT_UART_CTRL_BAUD_DIV_LSB) |
                    (1u << STUDENT_UART_CTRL_ENABLE_LSB);
    REG32(STUDENT_UART_CTRL(0)) = ctrl;
    check_eq("uart_ctrl_readback", REG32(STUDENT_UART_CTRL(0)), ctrl);

    REG32(STUDENT_UART_TXDATA(0)) = 0x55u;
    st = REG32(STUDENT_UART_STATUS(0));
    check_eq("uart_tx_busy_set",
             (st >> STUDENT_UART_STATUS_TX_BUSY_LSB) & 1u, 1u);

    check_cond("uart_tx_done",
               wait_reg_bits(STUDENT_UART_STATUS(0),
                             1u << STUDENT_UART_STATUS_TX_BUSY_LSB, 0u,
                             UART_TX_TIMEOUT), 1u, 0u);

    check_eq("uart_rx_still_empty",
             (REG32(STUDENT_UART_STATUS(0))
              >> STUDENT_UART_STATUS_RX_VALID_LSB) & 1u, 0u);

    REG32(STUDENT_UART_CTRL(0)) = 0u;
}

static void test_irq(void) {
    printf("-- IRQ_CTRL @ 0x%08x --\n", (unsigned) STUDENT_IRQ_CTRL0_BASE_ADDR);

    uint32_t mask0 = irq_ctrl_get_mask();
    irq_ctrl_set_all_en(0);
    irq_ctrl_mask_set(1u << CNN_IRQ_SRC_BIT);

    cnn_start();
    check_cond("irq_infer_done", cnn_wait_done(), 1u, 0u);

    check_cond("irq_pending_set",
               wait_reg_bits(IRQ_CTRL_STATUS, 1u << CNN_IRQ_SRC_BIT,
                             1u << CNN_IRQ_SRC_BIT, IRQ_SYNC_TIMEOUT), 1u, 0u);
    check_eq("irq_no_is_cnn", irq_ctrl_get_irq_no(), CNN_IRQ_SRC_BIT);

    cnn_start();
    check_cond("irq_pending_cleared",
               wait_reg_bits(IRQ_CTRL_STATUS, 1u << CNN_IRQ_SRC_BIT, 0u,
                             CNN_DONE_TIMEOUT), 1u, 0u);
    check_eq("irq_no_none", irq_ctrl_get_irq_no(), IRQ_CTRL_MAX);

    check_cond("irq_infer2_done", cnn_wait_done(), 1u, 0u);
    check_cond("irq_pending_reasserted",
               wait_reg_bits(IRQ_CTRL_STATUS, 1u << CNN_IRQ_SRC_BIT,
                             1u << CNN_IRQ_SRC_BIT, IRQ_SYNC_TIMEOUT), 1u, 0u);

    irq_ctrl_mask_clr(1u << CNN_IRQ_SRC_BIT);
    check_eq("irq_no_after_maskclr", irq_ctrl_get_irq_no(), IRQ_CTRL_MAX);

    irq_ctrl_set_mask(mask0);
    check_eq("irq_mask_restored", irq_ctrl_get_mask(), mask0);
}

int main(void) {
    printf("HAL self-test: cnn=0x%08x rlight=0x%08x oled=0x%08x "
           "uart=0x%08x irq=0x%08x\n",
           (unsigned) STUDENT_CNN0_BASE_ADDR,
           (unsigned) STUDENT_RLIGHT0_BASE_ADDR,
           (unsigned) STUDENT_OLED0_BASE_ADDR,
           (unsigned) STUDENT_UART0_BASE_ADDR,
           (unsigned) STUDENT_IRQ_CTRL0_BASE_ADDR);

    test_cnn();
    test_rlight();
    test_oled();
    test_uart();
    test_irq();

    printf("HAL TESTS: %u passed, %u failed\n", n_pass, n_fail);
    return (n_fail != 0) ? 1 : 0;
}
