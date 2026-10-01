/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 *
 * vprintf.c
 */

#include <stdio.h>
#include <stdarg.h>

int vprintf(const char *format, va_list ap)
{
	return vfprintf(stdout, format, ap);
}
