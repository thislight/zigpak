const REWRITER_PATH =
  process.env["ZIGPAK_REWRITER"] || "./zig-out/bin/zigpak-rewriter";

export async function rewriter(data: Uint8Array | ArrayBuffer | Buffer) {
  const { stdout, stderr } = await Bun.$`${REWRITER_PATH} < ${data}`.quiet();
  if (stderr.length > 0) {
    console.debug(stderr.toString());
  }
  return stdout;
}
