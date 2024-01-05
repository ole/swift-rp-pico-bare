/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef _PICO_BOOTROM_H
#define _PICO_BOOTROM_H

// platform.h
#ifndef __always_inline
#define __always_inline __attribute__((__always_inline__))
#endif
#define __force_inline __always_inline

/** \file bootrom.h
 * \defgroup pico_bootrom pico_bootrom
 * Access to functions and data in the RP2040 bootrom
 *
 * This header may be included by assembly code
 */

#ifndef __ASSEMBLER__

#ifdef __cplusplus
extern "C" {
#endif

/*!
 * \brief Lookup a bootrom function by code
 * \ingroup pico_bootrom
 * \param code the code
 * \return a pointer to the function, or NULL if the code does not match any bootrom function
 */
void *rom_func_lookup(unsigned int code);

// Bootrom function: rom_table_lookup
// Returns the 32 bit pointer into the ROM if found or NULL otherwise.
typedef void *(*rom_table_lookup_fn)(unsigned short *table, unsigned int code);

#if PICO_C_COMPILER_IS_GNU && (__GNUC__ >= 12)
// Convert a 16 bit pointer stored at the given rom address into a 32 bit pointer
static inline void *rom_hword_as_ptr(uint16_t rom_address) {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Warray-bounds"
    return (void *)(uintptr_t)*(uint16_t *)(uintptr_t)rom_address;
#pragma GCC diagnostic pop
}
#else
// Convert a 16 bit pointer stored at the given rom address into a 32 bit pointer
#define rom_hword_as_ptr(rom_address) (void *)(unsigned int *)(*(unsigned short *)(unsigned int *)(rom_address))
#endif

/*!
 * \brief Lookup a bootrom function by code. This method is forcibly inlined into the caller for FLASH/RAM sensitive code usage
 * \ingroup pico_bootrom
 * \param code the code
 * \return a pointer to the function, or NULL if the code does not match any bootrom function
 */
static __force_inline void *rom_func_lookup_inline(unsigned int code) {
    rom_table_lookup_fn rom_table_lookup = (rom_table_lookup_fn) rom_hword_as_ptr(0x18);
    unsigned short *func_table = (unsigned short *) rom_hword_as_ptr(0x14);
    return rom_table_lookup(func_table, code);
}

#ifdef __cplusplus
}
#endif

#endif // !__ASSEMBLER__
#endif
