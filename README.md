# Zigpak

Messagepack for Zig.

[![Checks](https://github.com/thislight/zigpak/actions/workflows/main.yml/badge.svg?branch=master&name=Checks)](https://github.com/thislight/zigpak/actions/workflows/main.yml)

- [API References (latest release)](https://zigpak.pages.dev/zigpak/)
- [API References (master)](https://master.zigpak.pages.dev/zigpak/)

Supported:

- Zig 0.12 (best effort)
- Zig 0.13
- Zig 0.14 (the master branch)

## Use In Your Project

Use a tarball link with `zig fetch --save`. You can find it in the "Tags" page. Some versions of zig can only fetch "tar.gz" files, so you may prefer this type.

```sh
zig fetch --save https://link-to-tarball
```

Assume the saved name is the default "zigpak". In the build script, refer the "zigpak" module.

```zig
// build.zig

pub fn build(b: *std.Build) void {
    // ...
    const exe: *std.Build.Compile;

    const zigpak = b.dependency("zigpak", .{
        .target = target,
        .optimize = optimize,
    }).module("zigpak");

    exe.root_module.addImport("zigpak", zigpak);
}
```

## License

Apache-2.0
