#!/usr/bin/env node
import { render } from "ink";
import { App } from "./app.js";
import { OrchestratorApp } from "./orchestrator-app.js";

type Mode =
  | { readonly kind: "state"; readonly path: string }
  | { readonly kind: "orch"; readonly path: string };

function parseArgs(argv: readonly string[]): Mode {
  const orchIdx = argv.indexOf("--orch");
  if (orchIdx !== -1) {
    if (orchIdx + 1 >= argv.length) {
      console.error("Usage: terminal-ui --orch <state-path>");
      process.exit(1);
    }
    return { kind: "orch", path: argv[orchIdx + 1]! };
  }

  const stateIdx = argv.indexOf("--state");
  if (stateIdx !== -1 && stateIdx + 1 < argv.length) {
    return { kind: "state", path: argv[stateIdx + 1]! };
  }

  console.error(
    "Usage: terminal-ui --state <path> | --orch <state-path>",
  );
  process.exit(1);
}

const mode = parseArgs(process.argv);

if (mode.kind === "orch") {
  render(<OrchestratorApp statePath={mode.path} />);
} else {
  render(<App statePath={mode.path} />);
}
