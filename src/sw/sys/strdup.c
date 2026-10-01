/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 *
 * strdup.c
 */

#include <string.h>
#include <stdlib.h>

char *strdup(const char *s)
{
	int l = strlen(s) + 1;
	char *d = malloc(l);

	if (d)
		memcpy(d, s, l);

	return d;
}
