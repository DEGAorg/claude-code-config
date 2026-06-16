import { describe, it, expect, beforeEach, afterEach } from "vitest";
import {
  mkdtempSync,
  rmSync,
  writeFileSync,
  readFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { updateFlow } from "../runner.js";

// ---------------------------------------------------------------------------
// Shape of the flow.json file as used by canon-tui. `active_since` is
// optional — old files written by pre-extension runners omit it and the
// TUI reads it with `.get("active_since", "")`.
// ---------------------------------------------------------------------------

interface FlowFile {
  steps: string[];
  labels: Record<string, string>;
  active: string;
  completed: string[];
  active_since?: string;
}

const ISO_8601_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

let tmpDir: string;
let flowPath: string;

function seedFlow(initial: Partial<FlowFile> = {}): void {
  const flow: FlowFile = {
    steps: ["scan", "signal", "risk", "execute", "log"],
    labels: {
      scan: "Scan",
      signal: "Signal",
      risk: "Risk",
      execute: "Execute",
      log: "Log",
    },
    active: "",
    completed: [],
    ...initial,
  };
  writeFileSync(flowPath, JSON.stringify(flow, null, 2) + "\n");
}

function readFlow(): FlowFile {
  return JSON.parse(readFileSync(flowPath, "utf-8")) as FlowFile;
}

beforeEach(() => {
  tmpDir = mkdtempSync(join(tmpdir(), "runner-active-since-"));
  flowPath = join(tmpDir, "flow.json");
});

afterEach(() => {
  rmSync(tmpDir, { recursive: true, force: true });
});

describe("updateFlow — active_since timestamp", () => {
  it("writes an ISO 8601 UTC active_since when active transitions to a new value", () => {
    seedFlow();

    updateFlow(flowPath, "scan", []);

    const flow = readFlow();
    expect(flow.active).toBe("scan");
    expect(flow.completed).toEqual([]);
    expect(flow.active_since).toBeDefined();
    expect(flow.active_since).toMatch(ISO_8601_UTC);
  });

  it("preserves active_since when called twice with the same active value", () => {
    seedFlow();

    updateFlow(flowPath, "scan", []);
    const first = readFlow();
    const firstTimestamp = first.active_since;
    expect(firstTimestamp).toMatch(ISO_8601_UTC);

    updateFlow(flowPath, "scan", []);
    const second = readFlow();
    expect(second.active_since).toBe(firstTimestamp);
  });

  it("omits active_since when active is the empty string", () => {
    seedFlow({
      active: "log",
      active_since: "2026-05-15T10:00:00.000Z",
    });

    updateFlow(flowPath, "", ["scan", "signal", "risk", "execute", "log"]);

    const flow = readFlow();
    expect(flow.active).toBe("");
    expect(flow.completed).toEqual([
      "scan",
      "signal",
      "risk",
      "execute",
      "log",
    ]);
    expect(flow.active_since).toBeUndefined();
    expect(Object.prototype.hasOwnProperty.call(flow, "active_since")).toBe(
      false,
    );
  });

  it("stamps active_since on a same-step update when a legacy file lacks it", () => {
    seedFlow({ active: "scan", completed: [] });

    updateFlow(flowPath, "scan", []);

    const flow = readFlow();
    expect(flow.active).toBe("scan");
    expect(flow.active_since).toBeDefined();
    expect(flow.active_since).toMatch(ISO_8601_UTC);
  });
});

describe("updateFlow — preserves DAG metadata", () => {
  const NODES = [
    { id: "scan", label: "Scan", type: "build" },
    { id: "execute", label: "Execute", type: "deploy" },
  ];
  const EDGES = [{ from: "scan", to: "execute" }];

  function seedWithDag(active = ""): void {
    seedFlow({ active });
    const flow = JSON.parse(readFileSync(flowPath, "utf-8")) as Record<
      string,
      unknown
    >;
    flow["nodes"] = NODES;
    flow["edges"] = EDGES;
    writeFileSync(flowPath, JSON.stringify(flow, null, 2) + "\n");
  }

  function readRaw(): Record<string, unknown> {
    return JSON.parse(readFileSync(flowPath, "utf-8")) as Record<
      string,
      unknown
    >;
  }

  it("keeps nodes and edges when active transitions to a new value", () => {
    seedWithDag();

    updateFlow(flowPath, "scan", []);

    const flow = readRaw();
    expect(flow["nodes"]).toEqual(NODES);
    expect(flow["edges"]).toEqual(EDGES);
    expect(flow["active"]).toBe("scan");
  });

  it("keeps nodes and edges across a full cycle including the empty-string reset", () => {
    seedWithDag();

    updateFlow(flowPath, "scan", []);
    updateFlow(flowPath, "execute", ["scan"]);
    updateFlow(flowPath, "", ["scan", "execute"]);

    const flow = readRaw();
    expect(flow["nodes"]).toEqual(NODES);
    expect(flow["edges"]).toEqual(EDGES);
    expect(flow["active"]).toBe("");
  });
});
