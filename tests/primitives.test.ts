import { expect, test, describe } from "bun:test";
import { unpack, pack } from "msgpackr";
import { rewriter } from "./tools.js";

function primitive(value: unknown) {
  const isValueBigInt = typeof value === "bigint";
  return async () => {
    const data = pack(value);
    const rewrited = await rewriter(data);
    // console.debug(value, data, rewrited);
    const result = unpack(rewrited);
    expect(isValueBigInt ? BigInt(result) : result).toEqual(value);
  };
}

test("nil", primitive(null));

describe("bool", () => {
  test("true", primitive(true));
  test("false", primitive(false));
});

function maxIntOf(signed: boolean, bits: 8 | 16 | 24 | 32): number;
function maxIntOf(signed: boolean, bits: number): number | bigint;

function maxIntOf(signed: boolean, bits: number) {
  const ibits = signed ? bits - 1 : bits;

  if (ibits >= 52) {
    return 2n ** BigInt(ibits) - 1n;
  } else {
    return 2 ** ibits - 1;
  }
}

function minIntOf(signed: boolean, bits: number) {
  if (!signed) {
    return 0;
  }

  const ibits = signed ? bits - 1 : bits;

  if (ibits >= 52) {
    return -(2n ** BigInt(ibits));
  } else {
    return -(2 ** ibits);
  }
}

describe("int", () => {
  test("0", primitive(0));
  test("1", primitive(1));
  test("-1", primitive(-1));

  for (const [signed, bits] of [8, 16, 32, 64].flatMap((x) => [
    [true, x] as const,
    [false, x] as const,
  ])) {
    test(`${signed ? "i" : "u"}${bits}max`, primitive(maxIntOf(signed, bits)));
    if (signed) {
      // No need to test 0 - they will be rewrited as fixint 0
      test(`i${bits}min`, primitive(minIntOf(true, bits)));
    }
  }

  test("f64maxint", primitive(Number.MAX_SAFE_INTEGER));
  test("f64minint", primitive(Number.MIN_SAFE_INTEGER));
});

describe("float", () => {
  test("0.5", primitive(0.5));
  test("-0.5", primitive(-0.5));
  test("f32maxint - 0.5", primitive(maxIntOf(true, 24) - 0.5));
  test("f32minint + 0.5", primitive(maxIntOf(true, 24) + 0.5));
  test("f64max", primitive(Number.MAX_VALUE));
  test("f64min", primitive(Number.MIN_VALUE));
});

const TEST_NBYTES = [
  0,
  12,
  maxIntOf(false, 8),
  maxIntOf(false, 16),
  maxIntOf(false, 16) * 2,
]; // We could not test too large binary...

function makeStr(bytes: number) {
  const strs = [] as string[];
  for (let i = 0; i < bytes; i++) {
    strs.push("a");
  }
  return strs.join();
}

const LARGEST_STR = makeStr(Math.max(...TEST_NBYTES));

describe("str", () => {
  for (const nbytes of TEST_NBYTES) {
    test(`${nbytes}c`, primitive(LARGEST_STR.slice(0, nbytes)));
  }
});

function makeBin(bytes: number) {
  return crypto.getRandomValues(new Uint8Array(bytes));
}

const LARGEST_BIN = makeBin(Math.max(...TEST_NBYTES));

describe("bin", () => {
  for (const nbytes of TEST_NBYTES) {
    test(`${nbytes}c`, primitive(LARGEST_BIN.slice(0, nbytes)));
  }
});
