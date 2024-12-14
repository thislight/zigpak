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
  test("0", primitive(0n));
  test("1", primitive(1n));
  test("i64max", primitive(2n ** 63n - 1n));
  test("i64min", primitive(-(2n ** 63n)));
});

describe("float", () => {
  test("0.0", primitive(0.0));
  test("1.5", primitive(1.0));
  test("f64maxint", primitive(Number.MAX_SAFE_INTEGER));
  test("f64minint", primitive(Number.MIN_SAFE_INTEGER));
  test("f64max", primitive(Number.MAX_VALUE));
  test("f64min", primitive(Number.MIN_VALUE));
});
