/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 *
 * strncat.c
 */

#include <string.h>

char *strncat(char *dst, const char *src, size_t n)
{
	char *q = strchr(dst, '\0');
	const char *p = src;
	char ch;

	while (n--) {
		*q++ = ch = *p++;
		if (!ch)
			return dst;
	}
	*q = '\0';

	return dst;
}
