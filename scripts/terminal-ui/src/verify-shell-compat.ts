/**
 * Verify that the bash shell writer produces JSON compatible
 * with the TypeScript TerminalUIState interface.
 *
 * Run: npx tsx src/verify-shell-compat.ts
 */

import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { readState } from "./write.js";
import type {
  LogLevel,
  Status,
  TerminalUIState,
} from "./types.js";
import { LOG_BUFFER_MAX } from "./types.js";

const SHELL_WRITER = join(
  import.meta.dirname,
  "../../terminal-ui-write.sh",
);

const VALID_STATUSES: readonly string[] = [
  "running",
  "paused",
  "idle",
  "error",
] satisfies readonly Status[];

const VALID_LOG_LEVELS: readonly string[] = [
  "info",
  "warn",
  "error",
  "debug",
] satisfies readonly LogLevel[];

let tmpDir = "";
let passed = 0;
let failed = 0;

function stateFile(): string {
  tmpDir = mkdtempSync(join(tmpdir(), "tui-verify-"));
  return join(tmpDir, "state.json");
}

function cleanup(): void {
  if (tmpDir) {
    rmSync(tmpDir, { recursive: true, force: true });
    tmpDir = "";
  }
}

function sh(file: string, ...args: string[]): void {
  execFileSync("bash", [SHELL_WRITER, file, ...args], {
    stdio: "pipe",
  });
}

function check(
  label: string,
  condition: boolean,
  detail?: string,
): void {
  if (condition) {
    passed++;
    console.log(`  ok: ${label}`);
  } else {
    failed++;
    console.error(
      `  FAIL: ${label}${detail ? ` — ${detail}` : ""}`,
    );
  }
}

function validateShape(state: TerminalUIState): void {
  check(
    "phase is string",
    typeof state.phase === "string",
    `got ${typeof state.phase}`,
  );
  check(
    "status is valid enum",
    VALID_STATUSES.includes(state.status),
    `got "${state.status}"`,
  );
  check(
    "startedAt is string",
    typeof state.startedAt === "string",
  );
  check(
    "startedAt is valid ISO 8601",
    !isNaN(Date.parse(state.startedAt)),
    state.startedAt,
  );
  check(
    "updatedAt is string",
    typeof state.updatedAt === "string",
  );
  check(
    "updatedAt is valid ISO 8601",
    !isNaN(Date.parse(state.updatedAt)),
    state.updatedAt,
  );
  check("logs is array", Array.isArray(state.logs));
  check(
    "error is string|null",
    state.error === null || typeof state.error === "string",
    `got ${typeof state.error}`,
  );
  check(
    "metrics is object",
    typeof state.metrics === "object" && state.metrics !== null,
  );

  for (const entry of state.logs) {
    check(
      `log.ts is valid ISO 8601`,
      typeof entry.ts === "string" &&
        !isNaN(Date.parse(entry.ts)),
      String(entry.ts),
    );
    check(
      `log.level is valid`,
      VALID_LOG_LEVELS.includes(entry.level),
      String(entry.level),
    );
    check(`log.msg is string`, typeof entry.msg === "string");
  }
}

async function testFreshCreate(): Promise<void> {
  console.log("\n1. Fresh state creation");
  const f = stateFile();
  try {
    sh(f, "phase=init", "status=idle");
    const state = await readState(f);
    check("readState returns non-null", state !== null);
    if (state) {
      validateShape(state);
      check("phase is init", state.phase === "init");
      check("status is idle", state.status === "idle");
      check("error is null", state.error === null);
      check("logs is empty", state.logs.length === 0);
    }
  } finally {
    cleanup();
  }
}

async function testPhaseStatusUpdate(): Promise<void> {
  console.log("\n2. Phase and status update");
  const f = stateFile();
  try {
    sh(f, "phase=init", "status=idle");
    sh(f, "phase=scaffold", "status=running");
    const state = await readState(f);
    check("readState returns non-null", state !== null);
    if (state) {
      validateShape(state);
      check(
        "phase updated to scaffold",
        state.phase === "scaffold",
      );
      check(
        "status updated to running",
        state.status === "running",
      );
    }
  } finally {
    cleanup();
  }
}

async function testLogEntries(): Promise<void> {
  console.log("\n3. Log entries");
  const f = stateFile();
  try {
    sh(f, "phase=run", "status=running");
    sh(f, 'log.info=Starting build', 'log.warn=Low memory');
    const state = await readState(f);
    check("readState returns non-null", state !== null);
    if (state) {
      validateShape(state);
      check("2 log entries", state.logs.length === 2);
      check(
        "first log is info",
        state.logs[0]?.level === "info",
      );
      check(
        "first log msg matches",
        state.logs[0]?.msg === "Starting build",
      );
      check(
        "second log is warn",
        state.logs[1]?.level === "warn",
      );
      check(
        "second log msg matches",
        state.logs[1]?.msg === "Low memory",
      );
    }
  } finally {
    cleanup();
  }
}

async function testMetrics(): Promise<void> {
  console.log("\n4. Metrics (JSON and string values)");
  const f = stateFile();
  try {
    sh(f, "phase=run", "status=running");
    sh(f, "metric.iteration=3", "metric.name=test-strat");
    const state = await readState(f);
    check("readState returns non-null", state !== null);
    if (state) {
      validateShape(state);
      check(
        "metric.iteration is number 3",
        state.metrics["iteration"] === 3,
        `got ${JSON.stringify(state.metrics["iteration"])}`,
      );
      check(
        "metric.name is string",
        state.metrics["name"] === "test-strat",
        `got ${JSON.stringify(state.metrics["name"])}`,
      );
    }
  } finally {
    cleanup();
  }
}

async function testMetricsMerge(): Promise<void> {
  console.log("\n5. Metrics shallow merge (new keys preserve old)");
  const f = stateFile();
  try {
    sh(f, "phase=run", "status=running", "metric.a=1");
    sh(f, "metric.b=2");
    const state = await readState(f);
    check("readState returns non-null", state !== null);
    if (state) {
      validateShape(state);
      check(
        "metric.a preserved",
        state.metrics["a"] === 1,
        `got ${JSON.stringify(state.metrics["a"])}`,
      );
      check(
        "metric.b added",
        state.metrics["b"] === 2,
        `got ${JSON.stringify(state.metrics["b"])}`,
      );
    }
  } finally {
    cleanup();
  }
}

async function testErrorSetAndClear(): Promise<void> {
  console.log("\n6. Error set and clear");
  const f = stateFile();
  try {
    sh(f, "status=error", "error=something broke");
    let state = await readState(f);
    check("readState returns non-null", state !== null);
    if (state) {
      validateShape(state);
      check(
        "error is string",
        state.error === "something broke",
        `got ${JSON.stringify(state.error)}`,
      );
      check("status is error", state.status === "error");
    }

    sh(f, "status=running", "error=");
    state = await readState(f);
    check("readState after clear returns non-null", state !== null);
    if (state) {
      validateShape(state);
      check(
        "error cleared to null",
        state.error === null,
        `got ${JSON.stringify(state.error)}`,
      );
      check(
        "status updated to running",
        state.status === "running",
      );
    }
  } finally {
    cleanup();
  }
}

async function testLogRingBuffer(): Promise<void> {
  console.log("\n7. Log ring buffer (>50 entries capped)");
  const f = stateFile();
  try {
    sh(f, "phase=run", "status=running");
    // Add 55 log entries one batch at a time
    for (let i = 0; i < 55; i++) {
      sh(f, `log.info=entry-${i}`);
    }
    const state = await readState(f);
    check("readState returns non-null", state !== null);
    if (state) {
      validateShape(state);
      check(
        `logs capped at ${LOG_BUFFER_MAX}`,
        state.logs.length === LOG_BUFFER_MAX,
        `got ${state.logs.length}`,
      );
      check(
        "oldest entries dropped (first is entry-5)",
        state.logs[0]?.msg === "entry-5",
        `got "${state.logs[0]?.msg}"`,
      );
      check(
        "newest entry retained (last is entry-54)",
        state.logs[state.logs.length - 1]?.msg === "entry-54",
        `got "${state.logs[state.logs.length - 1]?.msg}"`,
      );
    }
  } finally {
    cleanup();
  }
}

async function testFieldPreservation(): Promise<void> {
  console.log("\n8. Field preservation (update one, others unchanged)");
  const f = stateFile();
  try {
    sh(
      f,
      "phase=scaffold",
      "status=running",
      "log.info=hello",
      "metric.x=42",
    );
    const before = await readState(f);
    check("readState before returns non-null", before !== null);

    sh(f, "phase=run");
    const after = await readState(f);
    check("readState after returns non-null", after !== null);
    if (before && after) {
      validateShape(after);
      check(
        "phase changed to run",
        after.phase === "run",
      );
      check(
        "status preserved as running",
        after.status === "running",
      );
      check(
        "startedAt preserved",
        after.startedAt === before.startedAt,
      );
      check(
        "logs preserved",
        after.logs.length === 1 &&
          after.logs[0]?.msg === "hello",
      );
      check(
        "metrics preserved",
        after.metrics["x"] === 42,
      );
    }
  } finally {
    cleanup();
  }
}

async function testTsReadStateAcceptsShellOutput(): Promise<void> {
  console.log(
    "\n9. TS readState round-trip (shell write → TS read → TS write → TS read)",
  );
  const f = stateFile();
  try {
    // Shell creates state
    sh(
      f,
      "phase=demo",
      "status=running",
      "log.info=from shell",
      "metric.round=1",
    );
    const fromShell = await readState(f);
    check("readState from shell output", fromShell !== null);
    if (fromShell) {
      validateShape(fromShell);

      // TS overwrites same file — proves formats are compatible
      const { writeState } = await import("./write.js");
      await writeState(f, {
        phase: "demo-ts",
        appendLogs: [{ ts: new Date().toISOString(), level: "info", msg: "from ts" }],
      });
      const fromTs = await readState(f);
      check("readState from TS write", fromTs !== null);
      if (fromTs) {
        validateShape(fromTs);
        check(
          "phase updated by TS",
          fromTs.phase === "demo-ts",
        );
        check(
          "shell log preserved",
          fromTs.logs.some((l) => l.msg === "from shell"),
        );
        check(
          "TS log appended",
          fromTs.logs.some((l) => l.msg === "from ts"),
        );
        check(
          "metrics preserved across writers",
          fromTs.metrics["round"] === 1,
          `got ${JSON.stringify(fromTs.metrics["round"])}`,
        );
      }
    }
  } finally {
    cleanup();
  }
}

async function main(): Promise<void> {
  console.log("=== Shell → TS compatibility verification ===");

  await testFreshCreate();
  await testPhaseStatusUpdate();
  await testLogEntries();
  await testMetrics();
  await testMetricsMerge();
  await testErrorSetAndClear();
  await testLogRingBuffer();
  await testFieldPreservation();
  await testTsReadStateAcceptsShellOutput();

  console.log(`\n=== Results: ${passed} passed, ${failed} failed ===`);
  if (failed > 0) {
    process.exit(1);
  }
}

main().catch((err: unknown) => {
  console.error("Fatal error:", err);
  process.exit(2);
});
