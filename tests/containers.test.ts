import { expect, test, describe } from "bun:test";
import { pack, unpack } from "msgpackr";
import { rewriter } from "./tools";

function value(value: unknown) {
  return async () => {
    const data = pack(value);
    const rewrited = await rewriter(data);
    const unpacked = unpack(rewrited);
    expect(unpacked).toEqual(value);
  };
}

describe("array", () => {
  test("primitives", value([1, 2n ** 63n - 1n, 0.5, null]));
  test("strs", value(["Hello World!", "Hello World!", "Hello World!"]));
  test(
    "large bins",
    value([
      crypto.getRandomValues(new Uint8Array(16384)),
      crypto.getRandomValues(new Uint8Array(16384)),
      crypto.getRandomValues(new Uint8Array(16384)),
    ])
  );
  test(
    "mixed",
    value([
      1,
      2n ** 63n - 1n,
      crypto.getRandomValues(new Uint8Array(16384)),
      "Hello World!",
      crypto.getRandomValues(new Uint8Array(16384)),
      null,
      null,
      0.5,
    ])
  );
});

describe("array in array", () => {
  test("primitives", value([[1, 2n ** 63n - 1n, 0.5, null]]));
  test(
    "large bins",
    value([
      [
        crypto.getRandomValues(new Uint8Array(16384)),
        crypto.getRandomValues(new Uint8Array(16384)),
        crypto.getRandomValues(new Uint8Array(16384)),
      ],
      [crypto.getRandomValues(new Uint8Array(16384))],
    ])
  );
});

describe("map", () => {
  test(
    "mixed",
    value({
      a: 1,
      b: null,
      c: 0.5,
      d: "Hello World",
      e: crypto.getRandomValues(new Uint8Array(16384)),
      f: ["Hello", null, crypto.getRandomValues(new Uint8Array(32768))],
    })
  );
});

describe("map in array", () => {
  test(
    "mixed",
    value([
      { a: 1, b: null, c: 0.5 },
      {
        d: "Hello World",
        e: crypto.getRandomValues(new Uint8Array(16384)),
        f: ["Hello", null, crypto.getRandomValues(new Uint8Array(32768))],
      },
    ])
  );
});
