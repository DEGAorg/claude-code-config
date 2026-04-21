/**
 * Vitest spec for `StateSource`. Tests are written against the
 * contract, not the stub — they fail today and pass once item 7
 * wires in the real `LocalStateSource` (chokidar + tailer).
 */

import { mkdtempSync, rmSync, writeFileSync, appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { OrchestratorState } from "./orch-types.js";
import { LocalStateSource } from "./state-source.js";

function makeState(overrides: Partial<OrchestratorState> = {}): OrchestratorState {
  return {
    version: 1,
    plan: "test-plan",
    maxParallelWorkers: 4,
    mode: "background",
    items: [],
    finalReview: { status: "pending", result: null, reworkItems: [] },
    startedAt: "2026-04-21T00:00:00Z",
    updatedAt: "2026-04-21T00:00:00Z",
    lastHeartbeat: null,
    ...overrides,
  };
}

/** Resolve after at least `ms` milliseconds. */
function wait(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

describe("LocalStateSource", () => {
  let tmp: string;
  let statePath: string;
  let source: LocalStateSource;

  beforeEach(() => {
    tmp = mkdtempSync(join(tmpdir(), "state-source-"));
    statePath = join(tmp, "state.json");
    source = new LocalStateSource({ statePath });
  });

  afterEach(async () => {
    await source.dispose();
    rmSync(tmp, { recursive: true, force: true });
  });

  describe("readState", () => {
    it("returns null when the state file does not exist", async () => {
      await expect(source.readState()).resolves.toBeNull();
    });

    it("parses an existing state file", async () => {
      const state = makeState({ plan: "readable" });
      writeFileSync(statePath, JSON.stringify(state));
      await expect(source.readState()).resolves.toMatchObject({ plan: "readable" });
    });
  });

  describe("watchState", () => {
    it("tolerates a missing state file at subscription time", async () => {
      // Should not throw even though statePath does not exist yet.
      const unsub = source.watchState(() => {});
      await wait(50);
      unsub();
    });

    it("emits when the state file changes", async () => {
      writeFileSync(statePath, JSON.stringify(makeState({ plan: "v1" })));
      const received: OrchestratorState[] = [];
      const unsub = source.watchState((s) => {
        received.push(s);
      });
      // Allow watcher to settle + emit initial value.
      await wait(150);
      writeFileSync(statePath, JSON.stringify(makeState({ plan: "v2" })));
      // Allow file-system event to propagate.
      await wait(300);
      unsub();
      expect(received.length).toBeGreaterThanOrEqual(1);
      expect(received.at(-1)?.plan).toBe("v2");
    });
  });

  describe("tailLog", () => {
    it("yields lines appended after subscription", async () => {
      const logPath = join(tmp, "worker-1.log");
      writeFileSync(logPath, "first\n");
      const lines: string[] = [];
      const unsub = source.tailLog(logPath, (line) => {
        lines.push(line);
      });
      await wait(150);
      appendFileSync(logPath, "second\nthird\n");
      await wait(300);
      unsub();
      expect(lines).toContain("second");
      expect(lines).toContain("third");
    });

    it("tolerates a missing log file (waits for creation)", async () => {
      const logPath = join(tmp, "not-yet.log");
      const lines: string[] = [];
      const unsub = source.tailLog(logPath, (line) => {
        lines.push(line);
      });
      await wait(100);
      writeFileSync(logPath, "hello\n");
      await wait(300);
      unsub();
      expect(lines).toContain("hello");
    });
  });
});
