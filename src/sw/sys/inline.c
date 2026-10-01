/* SPDX-License-Identifier: LicenseRef-Baselibc
 * SPDX-FileCopyrightText: 2012 Petteri Aimonen <jpa at blc.mail.kapsi.fi>
 */
// Make an externally visible symbol out of inlined functions
#define __extern_inline
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
