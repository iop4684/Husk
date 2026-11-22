/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Stores into code, done through the JIT region's writable view (husk-tl-codewrite.c). */
#ifndef HUSK_TL_CODEWRITE_H
#define HUSK_TL_CODEWRITE_H

#include <stdbool.h>

/* From now on, stores into the executable view are carried out through the writable one, and the guest may map executable
 * memory of its own (it gets a piece of the JIT region). For mod loaders that hook the game (Geode). */
void tl_codewrite_enable(void);
bool tl_codewrite_enabled(void);
/* Stores carried out so far, for the log. */
long tl_codewrite_count(void);
/* The guest's own memory (outside the JIT region) that mprotect made executable and, for W^X, not writable: an inline-hook
 * library (Dobby) writes its trampolines there afterwards. Its pages then flip between writable and executable as they
 * fault, instead of the store ending the game. */
void tl_codewrite_note_exec(void *addr, unsigned long len);

#endif
