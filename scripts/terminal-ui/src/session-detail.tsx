import { Box, Text } from "ink";
import type { ItemReviewStatus, OrchestratorItem } from "./orch-types.js";

interface SessionDetailProps {
  readonly item: OrchestratorItem | null;
  /** Last N lines captured from the worker/reviewer tmux pane. */
  readonly outputLines: readonly string[];
  /** Current review status for the selected item. */
  readonly reviewStatus?: ItemReviewStatus;
}

export function SessionDetail({ item, outputLines, reviewStatus }: SessionDetailProps) {
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

      {outputLines.length === 0 ? (
        <Text dimColor>No output captured</Text>
      ) : (
        outputLines.map((line, idx) => (
          <Text key={idx} wrap="truncate">
            {line}
          </Text>
        ))
      )}
    </Box>
  );
}
