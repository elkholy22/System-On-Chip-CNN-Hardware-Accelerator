/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 * SPDX-FileCopyrightText: 2025 RVLab Contributors
 *
 * atox.c
 *
 * Modified by RVLab Contributors.
 * Reduced include template to explicit functions.
 */

#include <inttypes.h>
#include <stdlib.h>
#include <stdio.h>

int atoi(const char *nptr)
{
    return (int) strntoumax(nptr, NULL, 10, ~(size_t) 0);
}

long atol(const char *nptr)
{
    return (long) strntoumax(nptr, NULL, 10, ~(size_t) 0);
}

long long atoll(const char *nptr)
{
    return (long long) strntoumax(nptr, NULL, 10, ~(size_t) 0);
}
