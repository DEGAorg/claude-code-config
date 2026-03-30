import { Box, Text, useStdout } from "ink";
import type { MasterState, PlanEntry, PlanStatus } from "./orch-types.js";

interface MasterViewProps {
  readonly state: MasterState;
  readonly selectedIdx: number | null;
}

const STATUS_COLORS: Record<PlanStatus, string> = {
  running: "green",
  completed: "greenBright",
  failed: "red",
};

const STATUS_ICONS: Record<PlanStatus, string> = {
  running: "●",
  completed: "✓",
  failed: "✗",
};

function progressBar(
  done: number,
  total: number,
  width: number,
): string {
  if (total === 0) return "░".repeat(width);
  const filled = Math.round((done / total) * width);
  const empty = width - filled;
  return "█".repeat(filled) + "░".repeat(empty);
}

function formatAge(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(ms / 60_000);
  if (mins < 60) return `${mins}m`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h${mins % 60}m`;
  return `${Math.floor(hours / 24)}d`;
}

function PlanRow({
  plan,
  isSelected,
  barWidth,
}: {
  readonly plan: PlanEntry;
  readonly isSelected: boolean;
  readonly barWidth: number;
}) {
  const { progress } = plan;
  const color = STATUS_COLORS[plan.status];
  const icon = STATUS_ICONS[plan.status];
  const bar = progressBar(progress.done, progress.total, barWidth);
  const pct =
    progress.total > 0
      ? Math.round((progress.done / progress.total) * 100)
      : 0;

  const slug = plan.slug;

  return (
    <Box>
      <Box width={3}>
        <Text color={color}>{icon}</Text>
      </Box>
      <Box flexGrow={1}>
        {isSelected ? (
          <Text color="blueBright" bold>
            {slug}
          </Text>
        ) : (
          <Text>{slug}</Text>
        )}
      </Box>
      <Box width={barWidth + 2}>
        <Text color={color}>{bar}</Text>
      </Box>
      <Box width={10}>
        <Text>
          {progress.done}/{progress.total} ({pct}%)
        </Text>
      </Box>
      <Box width={6}>
        <Text color="green">{progress.running}r</Text>
      </Box>
      <Box width={6}>
        {progress.failed > 0 ? (
          <Text color="red">{progress.failed}f</Text>
        ) : (
          <Text dimColor>0f</Text>
        )}
      </Box>
      <Box width={6}>
        <Text dimColor>{formatAge(plan.startedAt)}</Text>
      </Box>
    </Box>
  );
}

export function MasterView({ state, selectedIdx }: MasterViewProps) {
  const { stdout } = useStdout();
  const termCols = stdout?.columns ?? 80;

  const fixedCols = 3 + 10 + 6 + 6 + 6 + 4;
  const barWidth = Math.max(8, Math.min(20, termCols - fixedCols - 30));

  const running = state.plans.filter((p) => p.status === "running").length;
  const completed = state.plans.filter(
    (p) => p.status === "completed",
  ).length;

  return (
    <Box flexDirection="column" borderStyle="single" paddingX={1}>
      <Box justifyContent="space-between">
        <Text bold>ALL PLANS</Text>
        <Text dimColor>
          {state.plans.length} plans: {running} running, {completed} done
        </Text>
      </Box>

      <Box marginTop={1}>
        <Box width={3}>
          <Text bold dimColor> </Text>
        </Box>
        <Box flexGrow={1}>
          <Text bold dimColor>
            PLAN
          </Text>
        </Box>
        <Box width={barWidth + 2}>
          <Text bold dimColor>
            PROGRESS
          </Text>
        </Box>
        <Box width={10}>
          <Text bold dimColor>
            ITEMS
          </Text>
        </Box>
        <Box width={6}>
          <Text bold dimColor>
            RUN
          </Text>
        </Box>
        <Box width={6}>
          <Text bold dimColor>
            FAIL
          </Text>
        </Box>
        <Box width={6}>
          <Text bold dimColor>
            AGE
          </Text>
        </Box>
      </Box>

      {state.plans.length === 0 ? (
        <Text dimColor>No plans registered</Text>
      ) : (
        state.plans.map((plan, idx) => (
          <PlanRow
            key={plan.slug}
            plan={plan}
            isSelected={idx === selectedIdx}
            barWidth={barWidth}
          />
        ))
      )}
    </Box>
  );
}
