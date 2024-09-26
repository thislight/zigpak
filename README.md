# Zigpak

Messagepack implementation for Zig.

Supported Zig 0.12 & 0.13

## Usage

Include this package and use the module "zigpak". This module include two sub fields:

- `zigpak.fmt` - The tools to emit messagepack values directly
- `zigpak.io` - Utilities to work with `std.io.Reader` and `std.io.Writer`.

`zigpak.fmt` has two kinds of writing functions and two kinds of reading functions:

- `prefix*` emits the prefixing of the value. Usually the values are no need to be transformed and can be written directly.
- `write*` accepts a value and writes into a buffer. The function name suffixed with `Sm` means this function uses run-time branching to reduce result size as possible.

- `readValue` and `.next` in `Value.LazyArray` and `Value.LazyMap` reads a value and returns in a dynamic-typed favour.
- `.nextOf` in `Value.LazyArray` and `Value.LazyMap` accepts a specific type and generate code to read only the specific type. This may reduce run-time branching and affect performance.

## License

Apache-2.0

