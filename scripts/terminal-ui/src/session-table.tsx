import { Box, Text, useStdout } from "ink";
import type { OrchestratorItem, ItemStatus } from "./orch-types.js";

interface SessionTableProps {
  readonly plan: string;
  readonly items: readonly OrchestratorItem[];
  readonly selectedId: number | null;
}

const STATUS_COLORS: Record<ItemStatus, string> = {
  queued: "gray",
  ready: "white",
  running: "green",
  review: "cyan",
  done: "greenBright",
  failed: "red",
  blocked: "yellow",
};

const STATUS_ICONS: Record<ItemStatus, string> = {
  queued: "·",
  ready: "○",
  running: "●",
  review: "◎",
  done: "✓",
  failed: "✗",
  blocked: "⊘",
};

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return text.slice(0, max - 1) + "…";
}

function formatWorker(item: OrchestratorItem): string {
  if (item.tmuxPane) return item.tmuxPane;
  if (item.worktree) return "bg";
  return "—";
}

function formatIteration(item: OrchestratorItem): string {
  if (item.status === "queued" || item.status === "blocked") return "—";
  return `${item.iteration}/${item.maxIterations}`;
}

function ItemRow({
  item,
  isSelected,
  descWidth,
}: {
  readonly item: OrchestratorItem;
  readonly isSelected: boolean;
  readonly descWidth: number;
}) {
  const color = STATUS_COLORS[item.status];
  const icon = STATUS_ICONS[item.status];
  const desc = truncate(item.description, descWidth);
  const idStr = String(item.id).padStart(2);

  return (
    <Box>
      <Box width={4}>
        {isSelected ? (
          <Text color="blueBright">{idStr}</Text>
        ) : (
          <Text>{idStr}</Text>
        )}
      </Box>
      <Box flexGrow={1}>
        {isSelected ? (
          <Text color="blueBright" bold>
            {desc}
          </Text>
        ) : (
          <Text>{desc}</Text>
        )}
      </Box>
      <Box width={10}>
        <Text color={color}>
          {icon} {item.status}
        </Text>
      </Box>
      <Box width={5}>
        <Text dimColor>{formatIteration(item)}</Text>
      </Box>
      <Box width={8}>
        <Text dimColor>{formatWorker(item)}</Text>
      </Box>
    </Box>
  );
}

export function SessionTable({
  plan,
  items,
  selectedId,
}: SessionTableProps) {
  const { stdout } = useStdout();
  const termCols = stdout?.columns ?? 80;

  const fixedCols = 4 + 10 + 5 + 8 + 4;
  const descWidth = Math.max(20, termCols - fixedCols - 4);

  const doneCount = items.filter((i) => i.status === "done").length;
  const activeCount = items.filter(
    (i) => i.status === "running" || i.status === "review",
  ).length;

  return (
    <Box
      flexDirection="column"
      borderStyle="single"
      borderBottom={false}
      paddingX={1}
    >
      <Box justifyContent="space-between">
        <Text bold>PLAN: {plan}</Text>
        <Text dimColor>
          {doneCount}/{items.length} done, {activeCount} active
        </Text>
      </Box>

      <Box marginTop={1}>
        <Box width={4}>
          <Text bold dimColor>#</Text>
        </Box>
        <Box flexGrow={1}>
          <Text bold dimColor>ITEM</Text>
        </Box>
        <Box width={10}>
          <Text bold dimColor>STATUS</Text>
        </Box>
        <Box width={5}>
          <Text bold dimColor>ITER</Text>
        </Box>
        <Box width={8}>
          <Text bold dimColor>WORKER</Text>
        </Box>
      </Box>

      {items.map((item) => (
        <ItemRow
          key={item.id}
          item={item}
          isSelected={item.id === selectedId}
          descWidth={descWidth}
        />
      ))}
    </Box>
  );
}
