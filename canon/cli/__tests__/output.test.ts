import { describe, expect, it } from "vitest";
import {
  formatError,
  formatSuccess,
  isPretty,
  stripFormatFlags,
} from "../output.js";

describe("isPretty", () => {
  it("returns true when --pretty is present", () => {
    expect(isPretty(["search", "--pretty", "bitcoin"])).toBe(true);
  });

  it("returns false when --pretty is absent", () => {
    expect(isPretty(["search", "bitcoin"])).toBe(false);
  });

  it("returns false for empty args", () => {
    expect(isPretty([])).toBe(false);
  });
});

describe("stripFormatFlags", () => {
  it("removes --pretty from args", () => {
    expect(stripFormatFlags(["search", "--pretty", "bitcoin"])).toEqual([
      "search",
      "bitcoin",
    ]);
  });

  it("returns args unchanged when no --pretty", () => {
    expect(stripFormatFlags(["search", "bitcoin"])).toEqual([
      "search",
      "bitcoin",
    ]);
  });

  it("handles empty args", () => {
    expect(stripFormatFlags([])).toEqual([]);
  });
});

describe("formatSuccess", () => {
  it("returns compact JSON by default", () => {
    const result = formatSuccess({ count: 3 }, false);
    expect(result).toBe('{"ok":true,"data":{"count":3}}');
  });

  it("returns indented JSON in pretty mode", () => {
    const result = formatSuccess({ count: 3 }, true);
    const parsed = JSON.parse(result) as { ok: boolean; data: unknown };
    expect(parsed.ok).toBe(true);
    expect(parsed.data).toEqual({ count: 3 });
    expect(result).toContain("\n");
  });

  it("handles arrays", () => {
    const result = formatSuccess([1, 2, 3], false);
    const parsed = JSON.parse(result) as {
      ok: boolean;
      data: number[];
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data).toEqual([1, 2, 3]);
  });

  it("handles null data", () => {
    const result = formatSuccess(null, false);
    expect(result).toBe('{"ok":true,"data":null}');
  });
});

describe("formatError", () => {
  it("returns compact JSON by default", () => {
    const result = formatError("not found", false);
    expect(result).toBe('{"ok":false,"error":"not found"}');
  });

  it("returns indented JSON in pretty mode", () => {
    const result = formatError("not found", true);
    const parsed = JSON.parse(result) as {
      ok: boolean;
      error: string;
    };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toBe("not found");
    expect(result).toContain("\n");
  });
});
