/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 * SPDX-FileCopyrightText: 2025 RVLab Contributors
 *
 * strtox.c
 *
 * Modified by RVLab Contributors.
 * Reduced include template to explicit functions.
 */

#include <stddef.h>
#include <stdlib.h>
#include <inttypes.h>

signed long strtol(const char *nptr, char **endptr, int base)
{
    return (signed long) strntoumax(nptr, endptr, base, ~(size_t) 0);
}

signed long long strtoll(const char *nptr, char **endptr, int base)
{
    return (signed long long) strntoumax(nptr, endptr, base, ~(size_t) 0);
}

unsigned long strtoul(const char *nptr, char **endptr, int base)
{
    return (unsigned long) strntoumax(nptr, endptr, base, ~(size_t) 0);
}

unsigned long long strtoull(const char *nptr, char **endptr, int base)
{
    return (unsigned long long) strntoumax(nptr, endptr, base, ~(size_t) 0);
}

intmax_t strtoimax(const char *nptr, char **endptr, int base)
{
    return (intmax_t) strntoumax(nptr, endptr, base, ~(size_t) 0);
}

uintmax_t strtoumax(const char *nptr, char **endptr, int base)
{
    return (uintmax_t) strntoumax(nptr, endptr, base, ~(size_t) 0);
}
