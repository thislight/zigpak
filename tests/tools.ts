const REWRITER_PATH =
  process.env["ZIGPAK_REWRITER"] || "./zig-out/bin/zigpak-rewriter";

export async function rewriter(data: Uint8Array | ArrayBuffer | Buffer) {
  const { stdout, stderr, exitCode } = await Bun.$`${REWRITER_PATH} < ${data}`
    .quiet()
    .nothrow();
  if (stderr.length > 0) {
    console.debug(stderr.toString());
  }
  if (exitCode !== 0) {
    throw new TypeError(`Failed with exit code ${exitCode}`);
  }
  return stdout;
}
