#ifndef STUDENT_OLED_HAL_H
#define STUDENT_OLED_HAL_H

#include <stdint.h>

#define OLED_GPIO (*(volatile uint32_t *)0x10400000u)

/* Pin-Bits (vgl. student_oled_gpio.sv). vdd/vbat aktiv-low: gesetzt = AUS. */
#define OLED_SDIN (1u << 0)
#define OLED_SCLK (1u << 1)
#define OLED_DC   (1u << 2)
#define OLED_RES  (1u << 3)
#define OLED_VBAT (1u << 4)
#define OLED_VDD  (1u << 5)

static uint32_t oled_shadow;

static inline void oled_w(void)            { OLED_GPIO = oled_shadow; }
static inline void oled_set(uint32_t bits) { oled_shadow |=  bits; oled_w(); }
static inline void oled_clr(uint32_t bits) { oled_shadow &= ~bits; oled_w(); }

static void oled_delay(volatile uint32_t n) { while (n--) { __asm__ volatile(""); } }

/* 1 Byte SPI: MSB zuerst, Sample an steigender sclk-Flanke, sclk ruht high. */
static void oled_spi(uint8_t b) {
    for (int i = 0; i < 8; i++) {
        if (b & 0x80u) oled_shadow |= OLED_SDIN; else oled_shadow &= ~OLED_SDIN;
        oled_shadow &= ~OLED_SCLK; oled_w();   /* sclk low, sdin gueltig */
        oled_shadow |=  OLED_SCLK; oled_w();   /* sclk high -> Sample     */
        b = (uint8_t)(b << 1);
    }
}
static void oled_cmd (uint8_t c) { oled_clr(OLED_DC); oled_spi(c); }   /* dc=0 */
static void oled_data(uint8_t d) { oled_set(OLED_DC); oled_spi(d); }   /* dc=1 */

/* SSD1306 128x32 Power-On + Init (Digilent-Sequenz). */
static void oled_init(void) {
    oled_shadow = OLED_VDD | OLED_VBAT | OLED_SCLK; /* vdd/vbat AUS, res=0, sclk high */
    oled_w();
    oled_delay(50000);

    oled_clr(OLED_VDD);                 /* VDD an */
    oled_delay(50000);

    oled_cmd(0xAE);                     /* display off */

    oled_clr(OLED_RES); oled_delay(10000);  /* Reset-Puls */
    oled_set(OLED_RES); oled_delay(10000);

    oled_cmd(0x8D); oled_cmd(0x14);     /* charge pump on */
    oled_cmd(0xD9); oled_cmd(0xF1);     /* pre-charge */

    oled_clr(OLED_VBAT);                /* VBAT an */
    oled_delay(1000000);               /* ~100ms settle */

    oled_cmd(0xA1);                     /* segment remap */
    oled_cmd(0xC8);                     /* COM scan dir */
    oled_cmd(0xDA); oled_cmd(0x02);     /* COM pins (128x32) */
    oled_cmd(0x81); oled_cmd(0x8F);     /* contrast */
    oled_cmd(0xA8); oled_cmd(0x1F);     /* multiplex = 32 */
    oled_cmd(0xD5); oled_cmd(0x80);     /* clock div */
    oled_cmd(0xD3); oled_cmd(0x00);     /* display offset */
    oled_cmd(0x40);                     /* start line 0 */
    oled_cmd(0x20); oled_cmd(0x00);     /* horizontal addressing */
    oled_cmd(0xA4);                     /* resume from RAM */
    oled_cmd(0xA6);                     /* normal (not inverted) */
    oled_cmd(0xAF);                     /* display on */
}

/* Fenster = ganze 128x32 setzen (fuer Framebuffer-Stream). */
static void oled_window_full(void) {
    oled_cmd(0x21); oled_cmd(0);   oled_cmd(127);  /* columns 0..127 */
    oled_cmd(0x22); oled_cmd(0);   oled_cmd(3);    /* pages   0..3   */
}

/* Test: ganzen Schirm auf val (0xFF=an, 0x00=aus). */
static void oled_fill(uint8_t val) {
    oled_window_full();
    for (int i = 0; i < 512; i++) oled_data(val);
}

/* 8x8-Ziffernfont (Zeilenformat, bit7=links). */
static const uint8_t oled_font8[10][8] = {
    {0x3C,0x66,0x6E,0x76,0x66,0x66,0x3C,0x00},
    {0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00},
    {0x3C,0x66,0x06,0x0C,0x18,0x30,0x7E,0x00},
    {0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00},
    {0x0C,0x1C,0x3C,0x6C,0x7E,0x0C,0x0C,0x00},
    {0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0x00},
    {0x1C,0x30,0x60,0x7C,0x66,0x66,0x3C,0x00},
    {0x7E,0x06,0x0C,0x18,0x30,0x30,0x30,0x00},
    {0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0x00},
    {0x3C,0x66,0x66,0x3E,0x06,0x0C,0x38,0x00},
};

static uint8_t oled_fb[512];   /* 128 Spalten x 4 Pages */

static inline void oled_px(int x, int y) {
    if (x < 0 || x > 127 || y < 0 || y > 31) return;
    oled_fb[(y >> 3) * 128 + x] |= (uint8_t)(1u << (y & 7));
}

/* Ziffer d gross (32x32, horizontal zentriert) anzeigen. */
static void oled_show_digit(unsigned d) {
    if (d > 9) d = 0;
    for (int i = 0; i < 512; i++) oled_fb[i] = 0;

    const uint8_t *g = oled_font8[d];
    const int SCALE = 4, X0 = 48;               /* 8*4=32 breit, zentriert */
    for (int fy = 0; fy < 8; fy++) {
        uint8_t row = g[fy];
        for (int fx = 0; fx < 8; fx++) {
            if (row & (uint8_t)(0x80u >> fx)) {
                for (int sy = 0; sy < SCALE; sy++)
                    for (int sx = 0; sx < SCALE; sx++)
                        oled_px(X0 + fx * SCALE + sx, fy * SCALE + sy);
            }
        }
    }
    oled_window_full();
    for (int i = 0; i < 512; i++) oled_data(oled_fb[i]);
}

#endif /* STUDENT_OLED_HAL_H */
