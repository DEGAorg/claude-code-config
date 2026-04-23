import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
} from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { run } from "../commands/wallet.js";

let root: string;
let origCwd: string;
let stdoutData: string;
let stderrData: string;
const origStdout = process.stdout.write.bind(process.stdout);
const origStderr = process.stderr.write.bind(process.stderr);

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "canon-wallet-cmd-"));
  origCwd = process.cwd();
  process.chdir(root);
  stdoutData = "";
  stderrData = "";
  process.stdout.write = ((chunk: string) => {
    stdoutData += chunk;
    return true;
  }) as typeof process.stdout.write;
  process.stderr.write = ((chunk: string) => {
    stderrData += chunk;
    return true;
  }) as typeof process.stderr.write;
  process.exitCode = undefined;
});

afterEach(() => {
  process.stdout.write = origStdout;
  process.stderr.write = origStderr;
  process.chdir(origCwd);
  rmSync(root, { recursive: true, force: true });
});

describe("wallet ensure", () => {
  it("creates a wallet on first run with created=true", async () => {
    await run(["ensure"]);
    const out = JSON.parse(stdoutData);
    expect(out.ok).toBe(true);
    expect(out.data.created).toBe(true);
    expect(out.data.address).toMatch(/^0x[0-9a-fA-F]{40}$/);
  });

  it("is idempotent on second run with created=false and same address", async () => {
    await run(["ensure"]);
    const first = JSON.parse(stdoutData).data.address;
    stdoutData = "";
    await run(["ensure"]);
    const second = JSON.parse(stdoutData);
    expect(second.data.created).toBe(false);
    expect(second.data.address).toBe(first);
  });

  it("pretty mode mentions funding on USDC.e on Polygon on first run", async () => {
    await run(["ensure", "--pretty"]);
    expect(stdoutData).toMatch(/USDC\.e/);
    expect(stdoutData).toMatch(/Polygon/);
  });
});

describe("wallet address", () => {
  it("errors when no wallet exists", async () => {
    await run(["address"]);
    const out = JSON.parse(stderrData);
    expect(out.ok).toBe(false);
    expect(out.error).toMatch(/no wallet/i);
  });

  it("prints the address after ensure", async () => {
    await run(["ensure"]);
    const expected = JSON.parse(stdoutData).data.address;
    stdoutData = "";
    await run(["address"]);
    const out = JSON.parse(stdoutData);
    expect(out.ok).toBe(true);
    expect(out.data.address).toBe(expected);
  });
});

describe("wallet info", () => {
  it("prints address and wallet file path after ensure", async () => {
    await run(["ensure"]);
    stdoutData = "";
    await run(["info"]);
    const out = JSON.parse(stdoutData);
    expect(out.ok).toBe(true);
    expect(out.data.address).toMatch(/^0x[0-9a-fA-F]{40}$/);
    expect(out.data.path).toMatch(/\.canon\/wallet\.env$/);
  });
});

describe("wallet unknown subcommand", () => {
  it("errors on unknown subcommand", async () => {
    await run(["nope"]);
    const out = JSON.parse(stderrData);
    expect(out.ok).toBe(false);
    expect(out.error).toMatch(/unknown/i);
  });
});
