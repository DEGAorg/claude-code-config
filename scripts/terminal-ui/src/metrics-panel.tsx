import { Box, Text } from "ink";

interface MetricsPanelProps {
  readonly metrics: Readonly<Record<string, unknown>>;
}

function formatValue(value: unknown): string {
  if (value === null || value === undefined) {
    return "—";
  }
  return String(value);
}

export function MetricsPanel({ metrics }: MetricsPanelProps) {
  const entries = Object.entries(metrics ?? {});

  if (entries.length === 0) {
    return (
      <Box
        borderStyle="single"
        borderTop={false}
        paddingX={1}
      >
        <Text dimColor>No metrics</Text>
      </Box>
    );
  }

  const rows: [string, unknown, string?, unknown?][] = [];
  for (let i = 0; i < entries.length; i += 2) {
    const [k1, v1] = entries[i]!;
    const next = entries[i + 1];
    if (next) {
      rows.push([k1, v1, next[0], next[1]]);
    } else {
      rows.push([k1, v1]);
    }
  }

  return (
    <Box
      flexDirection="column"
      borderStyle="single"
      borderTop={false}
      paddingX={1}
    >
      {rows.map(([k1, v1, k2, v2]) => (
        <Box key={k1} gap={1}>
          <Box minWidth={30}>
            <Text bold>{k1}: </Text>
            <Text>{formatValue(v1)}</Text>
          </Box>
          {k2 !== undefined ? (
            <Box>
              <Text bold>{k2}: </Text>
              <Text>{formatValue(v2)}</Text>
            </Box>
          ) : null}
        </Box>
      ))}
    </Box>
  );
}
