
#ifndef _STUDENT_UART_HAL_H
#define _STUDENT_UART_HAL_H

#include <stdint.h>
#include <rvlab.h>

static inline void uart_init(uint16_t baud_div) {
    REG32(STUDENT_UART_CTRL(0)) =
        ((uint32_t) baud_div << STUDENT_UART_CTRL_BAUD_DIV_LSB) |
        (1u << STUDENT_UART_CTRL_ENABLE_LSB);
}

static inline int uart_tx_busy(void) {
    return (REG32(STUDENT_UART_STATUS(0)) >> STUDENT_UART_STATUS_TX_BUSY_LSB) & 1u;
}

static inline int uart_rx_ready(void) {
    return (REG32(STUDENT_UART_STATUS(0)) >> STUDENT_UART_STATUS_RX_VALID_LSB) & 1u;
}

static inline void uart_putc(char c) {
    while (uart_tx_busy());
    REG32(STUDENT_UART_TXDATA(0)) = (uint8_t) c;
}

static inline uint8_t uart_getc(void) {
    while (!uart_rx_ready());
    return (uint8_t) (REG32(STUDENT_UART_RXDATA(0)) & 0xFF);
}

static inline void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

#endif /* _STUDENT_UART_HAL_H */
