import { useCurrentFrame, useVideoConfig, interpolate } from "remotion";
import { Terminal } from "./components/Terminal";
import { colors, fonts, timing } from "./styles/theme";

interface PhaseCardProps {
  label: string;
  subtitle: string;
}

/** Reusable phase transition card with slide-in and fade animations */
export const PhaseCard: React.FC<PhaseCardProps> = ({ label, subtitle }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const { fadeFrames } = timing;

  const opacity = interpolate(
    frame,
    [0, fadeFrames, durationInFrames - fadeFrames, durationInFrames],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  const labelX = interpolate(frame, [0, fadeFrames], [80, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const subtitleOpacity = interpolate(
    frame,
    [fadeFrames, fadeFrames + 10],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <div style={{ opacity }}>
      <Terminal title="canon">
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 24,
          }}
        >
          <div
            style={{
              fontSize: 72,
              fontWeight: 700,
              fontFamily: fonts.mono,
              color: colors.green,
              letterSpacing: 8,
              transform: `translateX(${labelX}px)`,
            }}
          >
            {label}
          </div>
          <div
            style={{
              fontSize: 28,
              fontFamily: fonts.mono,
              color: colors.textMuted,
              opacity: subtitleOpacity,
            }}
          >
            {subtitle}
          </div>
        </div>
      </Terminal>
    </div>
  );
};

/** Phase data for all 5 transition cards */
export const phases = [
  {
    id: "Scaffold",
    label: "SCAFFOLD",
    subtitle: "Setting up agents, skills, and project structure",
  },
  {
    id: "Strategy",
    label: "STRATEGY",
    subtitle: "Picking a market and designing the edge",
  },
  {
    id: "Build",
    label: "BUILD",
    subtitle: "The Conductor drives agents to write the strategy",
  },
  {
    id: "Review",
    label: "REVIEW",
    subtitle: "Automated review — agents iterate until it ships",
  },
  {
    id: "Run",
    label: "RUN",
    subtitle: "Strategy goes live — scanning markets, finding edges",
  },
] as const;
