/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 */
#include <string.h>

void bzero(void *dst, size_t n)
{
	memset(dst, 0, n);
}
