import { coverages, KCOV, KCOV_ARGS } from "./kcov";
import { mkdtempSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

const REWRITER =
  process.env["ZIGPAK_REWRITER"] || "./zig-out/bin/zigpak-rewriter";

function runRewriter(data: Uint8Array | ArrayBuffer | Buffer) {
  if (KCOV) {
    const collectPath = mkdtempSync(join(tmpdir(), "zigpak-"));
    coverages.push(collectPath);
    return Bun.$`${KCOV} ${KCOV_ARGS} --collect-only ${collectPath} ${REWRITER} < ${data}`;
  } else {
    return Bun.$`${REWRITER} < ${data}`;
  }
}

export async function rewriter(data: Uint8Array | ArrayBuffer | Buffer) {
  const { stdout, stderr, exitCode } = await runRewriter(data)
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
