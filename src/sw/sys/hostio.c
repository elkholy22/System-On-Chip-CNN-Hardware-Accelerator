/* SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */
#include <stdio.h>

#define OBUF_SIZE (1024) // must be a power of 2
#define IBUF_SIZE (1024) // must be a power of 2

typedef struct {
    char obuf[OBUF_SIZE]; // 0x3f000: written by device
    char ibuf[IBUF_SIZE]; // 0x3f400: written by debug host 
    int flags;       // 0x3f800: written by device
    int retval;      // 0x3f804: written by device
    int obuf_widx;   // 0x3f808: written by device
    int obuf_ridx;   // 0x3f80c: written by debug host
    int ibuf_widx;   // 0x3f810: written by debug host
    int ibuf_ridx;   // 0x3f814: written by device
} hostio_t;

extern volatile hostio_t hostio;

static int obuf_num_enqueued(void) {
    return (hostio.obuf_widx - hostio.obuf_ridx) & (OBUF_SIZE - 1);
}

static int ibuf_num_enqueued(void) {
    return (hostio.ibuf_widx - hostio.ibuf_ridx) & (IBUF_SIZE - 1);
}


// This occurs here on the rvlab CPU:
static void obuf_putc(char c) {
    int widx;
    while(obuf_num_enqueued() >= OBUF_SIZE-1);
    widx = hostio.obuf_widx;
    hostio.obuf[widx] = c;
    hostio.obuf_widx = (widx + 1) & (OBUF_SIZE-1);
}

char ibuf_getc(void) {
    int ridx;
    char ret;
    while(ibuf_num_enqueued() == 0);
    ridx = hostio.ibuf_ridx;
    ret = hostio.ibuf[ridx];
    hostio.ibuf_ridx = (ridx + 1) & (IBUF_SIZE-1);
    return ret;
}

static size_t
stdin_read(FILE *fp, char *bp, size_t n)
{
    int i;
    for(i=0;i<n;i++) {
        bp[i] = ibuf_getc();
    }
    return n;
}
static size_t
stdout_write(FILE *fp, const char *bp, size_t n)
{
    while(n-->0) {
        obuf_putc(*(bp++));
    }
    return n;
}
static struct File_methods _hostio_methods = {
    .write = stdout_write,
    .read = stdin_read
};
static struct File _hostio = {
    .vmt = &_hostio_methods
};

struct File *const stdin = &_hostio;
struct File *const stdout = &_hostio;
struct File *const stderr = &_hostio;

void hostio_init(void) {
    hostio.flags = 0;
    hostio.retval = 0;
    hostio.obuf_widx = 0;
    hostio.ibuf_ridx = 0;
}
