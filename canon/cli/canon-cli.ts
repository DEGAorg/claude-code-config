#!/usr/bin/env tsx
/**
 * Canon CLI — agent-callable trading tools for Polymarket.
 *
 * Entry point: parses top-level subcommands and routes to
 * command modules under ./commands/.
 */

const VERSION = "0.0.0";

const COMMANDS: Record<string, string> = {
  market: "Search markets, fetch prices, orderbooks, OHLCV",
  position: "List positions and calculate PnL",
  balance: "Fetch wallet balance",
  order: "Create, cancel, or list orders",
  kill: "Cancel all open orders (kill switch)",
  help: "Show help for a topic or list available skills",
};

function printHelp(): void {
  const lines = [
    `canon-cli v${VERSION}`,
    "",
    "Usage: canon-cli <command> [subcommand] [options]",
    "",
    "Commands:",
  ];

  for (const [name, desc] of Object.entries(COMMANDS)) {
    lines.push(`  ${name.padEnd(12)} ${desc}`);
  }

  lines.push("");
  lines.push("Global options:");
  lines.push("  --pretty       Human-readable output (default: JSON)");
  lines.push("  --help, -h     Show this help message");
  lines.push("  --version, -v  Show version");
  lines.push("");
  lines.push(
    "Examples:",
    '  canon-cli market search "bitcoin"',
    "  canon-cli position list --pretty",
    "  canon-cli help polymarket",
  );

  process.stdout.write(lines.join("\n") + "\n");
}

function printVersion(): void {
  process.stdout.write(`${VERSION}\n`);
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);

  if (args.length === 0 || args.includes("--help") || args.includes("-h")) {
    printHelp();
    return;
  }

  if (args.includes("--version") || args.includes("-v")) {
    printVersion();
    return;
  }

  const command = args[0];

  if (!command || !(command in COMMANDS)) {
    process.stderr.write(
      `Error: Unknown command "${command}"\n\n` +
        "Run 'canon-cli --help' for available commands.\n",
    );
    process.exitCode = 1;
    return;
  }

  // Subcommand modules are loaded dynamically to keep startup fast.
  // Each module exports a `run(args: string[]): Promise<void>` function.
  try {
    const mod = (await import(`./commands/${command}.js`)) as {
      run: (args: string[]) => Promise<void>;
    };
    await mod.run(args.slice(1));
  } catch (err: unknown) {
    if (
      err instanceof Error &&
      "code" in err &&
      (err as NodeJS.ErrnoException).code === "ERR_MODULE_NOT_FOUND"
    ) {
      process.stderr.write(
        `Error: Command "${command}" is not yet implemented.\n`,
      );
      process.exitCode = 1;
      return;
    }
    throw err;
  }
}

main().catch((err: unknown) => {
  process.stderr.write(
    `Fatal: ${err instanceof Error ? err.message : String(err)}\n`,
  );
  process.exitCode = 1;
});
