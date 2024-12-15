// SPDX: Apache-2.0
// This file is part of zigpak.
#pragma once

#include <stdint.h>
#include <stddef.h>

struct zigpak_unpack {
    uint8_t* buffer;
    size_t len;
};

struct zigpak_unpack zigpak_unpack_init(uint8_t * buffer, size_t len);

void zigpak_unpack_set_append(size_t olen, uint8_t *buffer, size_t len);
