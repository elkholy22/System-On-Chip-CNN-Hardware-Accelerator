/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 *
 * strcat.c
 */

#include <string.h>

char *strcat(char *dst, const char *src)
{
	strcpy(strchr(dst, '\0'), src);
	return dst;
}
