/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 *
 * strncpy.c
 */

#include <string.h>

char *strncpy(char *dst, const char *src, size_t n)
{
	char *q = dst;
	const char *p = src;
	char ch;

	while (n) {
		n--;
		*q++ = ch = *p++;
		if (!ch)
			break;
	}

	/* The specs say strncpy() fills the entire buffer with NUL.  Sigh. */
	memset(q, 0, n);

	return dst;
}
