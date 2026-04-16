/**
 * Output formatter — JSON by default (agent-parseable),
 * human-readable with --pretty flag.
 */

/** Structured CLI response envelope. */
export interface CliResult<T = unknown> {
  ok: boolean;
  data?: T;
  error?: string;
}

/** Check whether --pretty was passed in the args array. */
export function isPretty(args: readonly string[]): boolean {
  return args.includes("--pretty");
}

/** Strip --pretty from args so subcommands don't see it. */
export function stripFormatFlags(args: readonly string[]): string[] {
  return args.filter((a) => a !== "--pretty");
}

/**
 * Format a successful result.
 *
 * JSON mode: compact single-line JSON (easy for agents to parse).
 * Pretty mode: indented JSON with a header line.
 */
export function formatSuccess<T>(data: T, pretty: boolean): string {
  if (pretty) {
    return JSON.stringify({ ok: true, data }, null, 2);
  }
  return JSON.stringify({ ok: true, data });
}

/**
 * Format an error result.
 *
 * JSON mode: compact JSON with ok:false and error message.
 * Pretty mode: indented JSON with error details.
 */
export function formatError(message: string, pretty: boolean): string {
  if (pretty) {
    return JSON.stringify({ ok: false, error: message }, null, 2);
  }
  return JSON.stringify({ ok: false, error: message });
}

/**
 * Write a success result to stdout.
 *
 * Extracts --pretty from the original args to determine format.
 */
export function writeSuccess<T>(data: T, args: readonly string[]): void {
  const pretty = isPretty(args);
  process.stdout.write(formatSuccess(data, pretty) + "\n");
}

/**
 * Write an error result to stderr and set exit code.
 *
 * Extracts --pretty from the original args to determine format.
 */
export function writeError(
  message: string,
  args: readonly string[],
): void {
  const pretty = isPretty(args);
  process.stderr.write(formatError(message, pretty) + "\n");
  process.exitCode = 1;
}
