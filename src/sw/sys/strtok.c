/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 *
 * strtok.c
 */

#include <string.h>

char *strtok(char *s, const char *delim)
{
	static char *holder;

	return strtok_r(s, delim, &holder);
}
