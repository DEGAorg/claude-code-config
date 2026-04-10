import { describe, it, expect, vi, beforeEach } from "vitest";
import { existsSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

vi.mock("node:fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:fs")>();
  return {
    ...actual,
    existsSync: vi.fn(),
    mkdirSync: vi.fn(),
  };
});

vi.mock("playwright", () => ({
  chromium: {
    launch: vi.fn(),
  },
}));

const PROJECT_ROOT = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
);
const AUTH_DIR = resolve(PROJECT_ROOT, "auth");

beforeEach(() => {
  vi.resetAllMocks();
});

describe("getStorageStatePath", () => {
  it("returns path for the default account when no argument given", async () => {
    vi.mocked(existsSync).mockReturnValue(true);
    const { getStorageStatePath } = await import("../src/auth.js");

    const result = getStorageStatePath();

    expect(result).toBe(resolve(AUTH_DIR, "default", "storage-state.json"));
  });

  it("returns path for a named account", async () => {
    vi.mocked(existsSync).mockReturnValue(true);
    const { getStorageStatePath } = await import("../src/auth.js");

    const result = getStorageStatePath("team-alpha");

    expect(result).toBe(
      resolve(AUTH_DIR, "team-alpha", "storage-state.json"),
    );
  });

  it("creates the account directory when it does not exist", async () => {
    vi.mocked(existsSync).mockReturnValue(false);
    const { getStorageStatePath } = await import("../src/auth.js");

    getStorageStatePath("new-account");

    const expectedDir = resolve(AUTH_DIR, "new-account");
    expect(mkdirSync).toHaveBeenCalledWith(expectedDir, { recursive: true });
  });

  it("does not create directory when it already exists", async () => {
    vi.mocked(existsSync).mockReturnValue(true);
    const { getStorageStatePath } = await import("../src/auth.js");

    getStorageStatePath("existing");

    expect(mkdirSync).not.toHaveBeenCalled();
  });
});

describe("hasStoredSession", () => {
  it("returns true when storage-state.json exists", async () => {
    // First call: existsSync for directory (in getStorageStatePath)
    // Second call: existsSync for the file (in hasStoredSession)
    vi.mocked(existsSync).mockReturnValue(true);
    const { hasStoredSession } = await import("../src/auth.js");

    expect(hasStoredSession("acct1")).toBe(true);
  });

  it("returns false when storage-state.json does not exist", async () => {
    // Directory exists but file doesn't
    vi.mocked(existsSync)
      .mockReturnValueOnce(true)   // directory check in getStorageStatePath
      .mockReturnValueOnce(false); // file check in hasStoredSession
    const { hasStoredSession } = await import("../src/auth.js");

    expect(hasStoredSession("missing")).toBe(false);
  });

  it("uses default account when none specified", async () => {
    vi.mocked(existsSync).mockReturnValue(true);
    const { hasStoredSession } = await import("../src/auth.js");

    hasStoredSession();

    const expectedPath = resolve(
      AUTH_DIR,
      "default",
      "storage-state.json",
    );
    // existsSync should have been called with the default account path
    expect(existsSync).toHaveBeenCalledWith(expectedPath);
  });
});

describe("validateSession", () => {
  it("returns false when no stored session exists", async () => {
    vi.mocked(existsSync)
      .mockReturnValueOnce(true)   // directory check
      .mockReturnValueOnce(false); // file check
    const { validateSession } = await import("../src/auth.js");

    const result = await validateSession("no-session");

    expect(result).toBe(false);
  });

  it("returns true when browser finds logged-in indicator", async () => {
    vi.mocked(existsSync).mockReturnValue(true);

    const { chromium } = await import("playwright");
    const mockPage = {
      goto: vi.fn().mockResolvedValue(undefined),
      waitForSelector: vi.fn().mockResolvedValue({}),
    };
    const mockContext = {
      newPage: vi.fn().mockResolvedValue(mockPage),
      close: vi.fn().mockResolvedValue(undefined),
    };
    const mockBrowser = {
      newContext: vi.fn().mockResolvedValue(mockContext),
      close: vi.fn().mockResolvedValue(undefined),
    };
    vi.mocked(chromium.launch).mockResolvedValue(mockBrowser as never);

    const { validateSession } = await import("../src/auth.js");

    const result = await validateSession("valid-acct");

    expect(result).toBe(true);
    expect(mockBrowser.close).toHaveBeenCalled();
  });

  it("returns false when browser finds no logged-in indicator", async () => {
    vi.mocked(existsSync).mockReturnValue(true);

    const { chromium } = await import("playwright");
    const mockPage = {
      goto: vi.fn().mockResolvedValue(undefined),
      waitForSelector: vi.fn().mockRejectedValue(new Error("timeout")),
    };
    const mockContext = {
      newPage: vi.fn().mockResolvedValue(mockPage),
      close: vi.fn().mockResolvedValue(undefined),
    };
    const mockBrowser = {
      newContext: vi.fn().mockResolvedValue(mockContext),
      close: vi.fn().mockResolvedValue(undefined),
    };
    vi.mocked(chromium.launch).mockResolvedValue(mockBrowser as never);

    const { validateSession } = await import("../src/auth.js");

    const result = await validateSession("expired-acct");

    expect(result).toBe(false);
    expect(mockBrowser.close).toHaveBeenCalled();
  });

  it("returns false and closes browser on unexpected error", async () => {
    vi.mocked(existsSync).mockReturnValue(true);

    const { chromium } = await import("playwright");
    const mockBrowser = {
      newContext: vi.fn().mockRejectedValue(new Error("crash")),
      close: vi.fn().mockResolvedValue(undefined),
    };
    vi.mocked(chromium.launch).mockResolvedValue(mockBrowser as never);

    const { validateSession } = await import("../src/auth.js");

    const result = await validateSession("crash-acct");

    expect(result).toBe(false);
    expect(mockBrowser.close).toHaveBeenCalled();
  });
});
