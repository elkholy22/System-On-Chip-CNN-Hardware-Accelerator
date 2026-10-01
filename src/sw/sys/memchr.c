/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 *
 * memchr.c
 */

#include <stddef.h>
#include <string.h>

void *memchr(const void *s, int c, size_t n)
{
	const unsigned char *sp = s;

	while (n--) {
		if (*sp == (unsigned char)c)
			return (void *)sp;
		sp++;
	}

	return NULL;
}
