/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 */
#include <string.h>

char *strtok_r(char *s, const char *delim, char **holder)
{
	if (s)
		*holder = s;

	do {
		s = strsep(holder, delim);
	} while (s && !*s);

	return s;
}
