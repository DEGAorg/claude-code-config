/**
 * Runner: executes all POC test suites in order with structured pass/fail output.
 *
 * Each test file is a standalone script that exits with 0 (all passed) or 1 (failures).
 * This runner spawns them as subprocesses, streams their output, and collects results
 * into a final summary table.
 *
 * Usage: npx tsx src/run-all.ts
 */
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));

interface SuiteResult {
  name: string;
  file: string;
  exitCode: number;
  passed: number;
  failed: number;
  skipped: number;
  duration: number;
  error?: string | undefined;
}

const SUITES = [
  { name: "Read-Only", file: "test-read-only.ts" },
  { name: "Auth", file: "test-auth.ts" },
  { name: "Orders", file: "test-orders.ts" },
  { name: "WebSocket", file: "test-websocket.ts" },
  { name: "DataAPI-Positions", file: "test-data-api-positions.ts" },
  { name: "DataAPI-Activity", file: "test-data-api-activity.ts" },
  { name: "DataAPI-Trades", file: "test-data-api-trades.ts" },
  { name: "DataAPI-Profile", file: "test-data-api-profile.ts" },
];

function parseSummaryLine(output: string): {
  passed: number;
  failed: number;
  skipped: number;
} {
  // Match "Result: X/Y passed" format (read-only, websocket)
  const slashMatch = output.match(
    /Result:\s+(\d+)\/(\d+)\s+passed/,
  );
  if (slashMatch) {
    const passed = parseInt(slashMatch[1] ?? "0", 10);
    const total = parseInt(slashMatch[2] ?? "0", 10);
    return { passed, failed: total - passed, skipped: 0 };
  }

  // Match "Result: X passed, Y failed, Z skipped" format (auth, orders)
  const fullMatch = output.match(
    /Result:\s+(\d+)\s+passed,\s+(\d+)\s+failed,\s+(\d+)\s+skipped/,
  );
  if (fullMatch) {
    return {
      passed: parseInt(fullMatch[1] ?? "0", 10),
      failed: parseInt(fullMatch[2] ?? "0", 10),
      skipped: parseInt(fullMatch[3] ?? "0", 10),
    };
  }

  return { passed: 0, failed: 0, skipped: 0 };
}

function runSuite(
  suite: { name: string; file: string },
): Promise<SuiteResult> {
  return new Promise((resolve) => {
    const filePath = join(__dirname, suite.file);
    const start = Date.now();
    let stdout = "";
    let stderr = "";

    const child = spawn(
      "npx",
      ["tsx", filePath],
      {
        cwd: join(__dirname, ".."),
        env: process.env,
        stdio: ["ignore", "pipe", "pipe"],
      },
    );

    child.stdout.on("data", (chunk: Buffer) => {
      const text = chunk.toString();
      stdout += text;
      process.stdout.write(text);
    });

    child.stderr.on("data", (chunk: Buffer) => {
      const text = chunk.toString();
      stderr += text;
      process.stderr.write(text);
    });

    child.on("error", (err) => {
      resolve({
        name: suite.name,
        file: suite.file,
        exitCode: 1,
        passed: 0,
        failed: 0,
        skipped: 0,
        duration: Date.now() - start,
        error: `Failed to spawn: ${err.message}`,
      });
    });

    child.on("close", (code) => {
      const elapsed = Date.now() - start;
      const counts = parseSummaryLine(stdout);
      resolve({
        name: suite.name,
        file: suite.file,
        exitCode: code ?? 1,
        ...counts,
        duration: elapsed,
        error: code !== 0 && stderr ? stderr.trim().slice(0, 200) : undefined,
      });
    });
  });
}

async function main(): Promise<void> {
  console.log("╔══════════════════════════════════════════════╗");
  console.log("║   pmxt POC — Full Test Suite                ║");
  console.log("╚══════════════════════════════════════════════╝\n");

  const results: SuiteResult[] = [];

  for (const suite of SUITES) {
    console.log(`\n${"─".repeat(60)}`);
    console.log(`  Running: ${suite.name} (${suite.file})`);
    console.log(`${"─".repeat(60)}\n`);

    const result = await runSuite(suite);
    results.push(result);

    const icon = result.exitCode === 0 ? "PASS" : "FAIL";
    console.log(`\n  >> ${suite.name}: ${icon} (${result.duration}ms)\n`);
  }

  // Final summary
  console.log("\n" + "═".repeat(60));
  console.log("  FINAL SUMMARY");
  console.log("═".repeat(60));
  console.log(
    "Suite          | Status | Passed | Failed | Skipped | Duration",
  );
  console.log(
    "---------------|--------|--------|--------|---------|----------",
  );

  let totalPassed = 0;
  let totalFailed = 0;
  let totalSkipped = 0;
  let allSuitesOk = true;

  for (const r of results) {
    const name = r.name.padEnd(15);
    const status = (r.exitCode === 0 ? "PASS" : "FAIL").padEnd(6);
    const passed = String(r.passed).padEnd(6);
    const failed = String(r.failed).padEnd(6);
    const skipped = String(r.skipped).padEnd(7);
    const dur = `${r.duration}ms`;

    console.log(
      `${name}| ${status} | ${passed} | ${failed} | ${skipped} | ${dur}`,
    );
    if (r.error) {
      console.log(
        `               |        | ${r.error.slice(0, 60)}`,
      );
    }

    totalPassed += r.passed;
    totalFailed += r.failed;
    totalSkipped += r.skipped;
    if (r.exitCode !== 0) allSuitesOk = false;
  }

  console.log("═".repeat(60));
  console.log(
    `Totals: ${totalPassed} passed, ${totalFailed} failed, ${totalSkipped} skipped`,
  );
  console.log(
    `Overall: ${allSuitesOk ? "ALL SUITES PASSED" : "SOME SUITES FAILED"}`,
  );
  console.log("═".repeat(60));

  if (!allSuitesOk) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
