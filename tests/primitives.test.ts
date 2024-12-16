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

describe("int", () => {
  test("0", primitive(0));
  test("1", primitive(1));
  test("-1", primitive(-1));

  test("i64max", primitive(2n ** 63n - 1n));
  test("i64min", primitive(-(2n ** 63n)));

  test("f64maxint", primitive(Number.MAX_SAFE_INTEGER));
  test("f64minint", primitive(Number.MIN_SAFE_INTEGER));
});

describe("float", () => {
  test("0.5", primitive(0.5));
  test("1.5", primitive(1.0));
  test("f64max", primitive(Number.MAX_VALUE));
  test("f64min", primitive(Number.MIN_VALUE));
});

function makeStr(bytes: number) {
  const strs = [] as string[];
  for (let i = 0; i < bytes; i++) {
    strs.push("a");
  }
  return strs.join();
}

describe("str", () => {
  test("0c", primitive(makeStr(0)));
  test("12c", primitive("Hello World!"));
  test("16384c", primitive(makeStr(16384)));
  test("32698c", primitive(makeStr(16384)));
});

function makeBin(bytes: number) {
  return crypto.getRandomValues(new Uint8Array(bytes));
}

describe("bin", () => {
  test("0b", primitive(makeBin(0)));
  test("12b", primitive(makeBin(12)));
  test("16384b", primitive(makeBin(16384)));
  test("32698b", primitive(makeBin(32698)));
});
