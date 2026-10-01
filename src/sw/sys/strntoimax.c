/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 *
 * strntoimax.c
 *
 * strntoimax()
 */

#include <stddef.h>
#include <inttypes.h>

intmax_t strntoimax(const char *nptr, char **endptr, int base, size_t n)
{
	return (intmax_t) strntoumax(nptr, endptr, base, n);
}
