/**
 * CLI command registry — single source of truth for the subcommands
 * that `canon-cli` dispatches to.
 *
 * Each entry is `{ description, load }`. `load` is a lazy importer
 * (dynamic import) so adding a command does not slow down startup of
 * the others, and a broken adapter inside one command does not
 * prevent the rest of the CLI from running.
 *
 * `canon-cli.ts` currently dispatches via `import(./commands/${name}.js)`
 * keyed by its own `COMMANDS` map; consumers that need a typed,
 * machine-readable list of commands (TUI, docs generator) should
 * import from this module instead.
 */

export interface CommandRunner {
  run: (args: string[]) => Promise<void>;
}

export interface CommandModule {
  /** Short description, surfaced in `canon-cli --help`. */
  readonly description: string;
  /** Lazy loader — defers the import until the command is invoked. */
  load(): Promise<CommandRunner>;
}

export const commands: Record<string, CommandModule> = {
  market: {
    description: "Search markets, fetch prices, orderbooks, OHLCV",
    load: () => import("./market.js"),
  },
  position: {
    description: "List positions and calculate PnL",
    load: () => import("./position.js"),
  },
  balance: {
    description: "Fetch wallet balance",
    load: () => import("./balance.js"),
  },
  order: {
    description: "Create, cancel, or list orders",
    load: () => import("./order.js"),
  },
  kill: {
    description: "Cancel all open orders (kill switch)",
    load: () => import("./kill.js"),
  },
  onboard: {
    description:
      "Wallet onboarding: --status / --execute drive the venue chain " +
      "(funder → approvals → CLOB creds); legacy USDC.e swap modes still work.",
    load: () => import("./onboard.js"),
  },
  wallet: {
    description: "Manage the project-local burner wallet (ensure/address/info)",
    load: () => import("./wallet.js"),
  },
  help: {
    description: "Show help for a topic or list available skills",
    load: () => import("./help.js"),
  },
};

export function listCommands(): string[] {
  return Object.keys(commands);
}
