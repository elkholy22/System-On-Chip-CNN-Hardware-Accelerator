/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 *
 * strrchr.c
 */

#include <string.h>

char *strrchr(const char *s, int c)
{
	const char *found = NULL;

	while (*s) {
		if (*s == (char)c)
			found = s;
		s++;
	}

	return (char *)found;
}

