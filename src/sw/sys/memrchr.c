/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 *
 * memrchr.c
 */

#include <stddef.h>
#include <string.h>

void *memrchr(const void *s, int c, size_t n)
{
	const unsigned char *sp = (const unsigned char *)s + n - 1;

	while (n--) {
		if (*sp == (unsigned char)c)
			return (void *)sp;
		sp--;
	}

	return NULL;
}
