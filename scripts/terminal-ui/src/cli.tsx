#!/usr/bin/env node
import { render } from "ink";
import { App } from "./app.js";

function parseArgs(argv: readonly string[]): string {
  const idx = argv.indexOf("--state");
  if (idx === -1 || idx + 1 >= argv.length) {
    console.error("Usage: terminal-ui --state <path>");
    process.exit(1);
  }
  return argv[idx + 1]!;
}

const statePath = parseArgs(process.argv);
render(<App statePath={statePath} />);
