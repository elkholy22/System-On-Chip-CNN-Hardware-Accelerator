/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 *
 * strstr.c
 */

#include <string.h>

char *strstr(const char *haystack, const char *needle)
{
	return (char *)memmem(haystack, strlen(haystack), needle,
			      strlen(needle));
}
