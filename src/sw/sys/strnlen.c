/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 *
 * strnlen()
 */

#include <string.h>

size_t strnlen(const char *s, size_t maxlen)
{
	const char *ss = s;

	/* Important: the maxlen test must precede the reference through ss;
	   since the byte beyond the maximum may segfault */
	while ((maxlen > 0) && *ss) {
		ss++;
		maxlen--;
	}
	return ss - s;
}
