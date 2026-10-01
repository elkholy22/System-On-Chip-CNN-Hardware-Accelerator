/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 *
 * strndup.c
 */

#include <string.h>
#include <stdlib.h>

char *strndup(const char *s, size_t n)
{
	int l = n > strlen(s) ? strlen(s) + 1 : n + 1;
	char *d = malloc(l);

	if (!d)
		return NULL;
	
	memcpy(d, s, l);
	d[n] = '\0';
	return d;
}
