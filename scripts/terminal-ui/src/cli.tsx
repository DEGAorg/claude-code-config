#!/usr/bin/env node
import { render } from "ink";
import { App } from "./app.js";
import {
  OrchestratorApp,
  MasterOrchestratorApp,
} from "./orchestrator-app.js";

type Mode =
  | { readonly kind: "state"; readonly path: string }
  | { readonly kind: "orch"; readonly path: string }
  | { readonly kind: "orch-master"; readonly path: string };

function parseArgs(argv: readonly string[]): Mode {
  const masterIdx = argv.indexOf("--orch-master");
  if (masterIdx !== -1) {
    if (masterIdx + 1 >= argv.length) {
      console.error(
        "Usage: terminal-ui --orch-master <master.json-path>",
      );
      process.exit(1);
    }
    return { kind: "orch-master", path: argv[masterIdx + 1]! };
  }

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
    "Usage: terminal-ui --state <path> | --orch <state-path> | --orch-master <master-path>",
  );
  process.exit(1);
}

const mode = parseArgs(process.argv);

if (mode.kind === "orch-master") {
  render(<MasterOrchestratorApp masterPath={mode.path} />);
} else if (mode.kind === "orch") {
  render(<OrchestratorApp statePath={mode.path} />);
} else {
  render(<App statePath={mode.path} />);
}
