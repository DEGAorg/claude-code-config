import { Box, Text, useStdout } from "ink";
import type { ItemReviewStatus, OrchestratorItem } from "./orch-types.js";

interface SessionDetailProps {
  readonly item: OrchestratorItem | null;
  /** Last N lines captured from the worker/reviewer tmux pane. */
  readonly outputLines: readonly string[];
  /** Current review status for the selected item. */
  readonly reviewStatus?: ItemReviewStatus;
  /** Number of rows consumed by header, table, and footer above this component. */
  readonly reservedRows?: number;
}

export function SessionDetail({ item, outputLines, reviewStatus, reservedRows }: SessionDetailProps) {
  const { stdout } = useStdout();
  const termRows = stdout?.rows ?? 40;
  // Available lines = terminal height - reserved rows (header+table+footer+borders)
  // Subtract 3 for this component's own chrome (border + header line + padding)
  const availableLines = Math.max(3, termRows - (reservedRows ?? 0) - 3);
  const visibleLines = outputLines.slice(-availableLines);
  if (!item) {
    return (
      <Box
        flexGrow={1}
        flexDirection="column"
        borderStyle="single"
        borderTop={false}
        paddingX={1}
        overflow="hidden"
      >
        <Text dimColor>Select an item to view output</Text>
      </Box>
    );
  }

  const isReviewing = reviewStatus === "reviewing";
  const roleLabel = isReviewing ? "reviewer" : "worker";

  const headerColor = isReviewing
    ? "magenta"
    : item.status === "running"
      ? "green"
      : item.status === "failed"
        ? "red"
        : "cyan";

  return (
    <Box
      flexGrow={1}
      flexDirection="column"
      borderStyle="single"
      borderTop={false}
      paddingX={1}
      overflow="hidden"
    >
      <Box gap={1}>
        <Text color={headerColor} bold>
          {roleLabel} {item.tmuxPane ?? `item-${item.id}`}:
        </Text>
        <Text>
          item {item.id} — {item.description}
        </Text>
        <Box flexGrow={1} />
        <Text dimColor>
          iter {item.iteration}/{item.maxIterations}
        </Text>
      </Box>

      {visibleLines.length === 0 ? (
        <Text dimColor>No output captured</Text>
      ) : (
        visibleLines.map((line, idx) => (
          <Text key={idx} wrap="truncate">
            {line}
          </Text>
        ))
      )}
    </Box>
  );
}
