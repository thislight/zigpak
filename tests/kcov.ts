import { afterAll } from "bun:test";
import { mkdir, rm } from "node:fs/promises";

export const KCOV = process.env["KCOV"];
export const KCOV_ARGS = process.env["KCOV_ARGS"] ?? "";
const KCOV_REPORT = process.env["KCOV_REPORT"] ?? "./zig-out/cov";

export const coverages = [] as string[];

if (KCOV) {
  afterAll(async () => {
    await mkdir(KCOV_REPORT, { recursive: true });
    await Bun.$`${KCOV} ${KCOV_ARGS} --merge ${KCOV_REPORT.split(" ")} ${coverages}`;
    await Promise.all(coverages.map((x) => rm(x, { recursive: true })));
  });
}
