/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "bootrom.h"

void *rom_func_lookup(unsigned int code) {
    return rom_func_lookup_inline(code);
}
