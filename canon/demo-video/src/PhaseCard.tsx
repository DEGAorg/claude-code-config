import {
  AbsoluteFill,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
} from "remotion";
import { ScanLines } from "./components/ScanLines";
import { colors, fonts, timing } from "./styles/theme";

interface PhaseCardProps {
  label: string;
  subtitle: string;
}

/**
 * Phase transition card — snappy 1.5s title slam.
 *
 * Sequence:
 * 0-3:   Black
 * 3-8:   Label slams in from right with green glow flash
 * 10-18: Subtitle fades up
 * Last 8: Everything fades to black
 *
 * No grid — just black + scan lines + typography.
 */
export const PhaseCard: React.FC<PhaseCardProps> = ({ label, subtitle }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const { fadeFrames } = timing;

  // Label slides in from right and snaps to center
  const labelX = interpolate(frame, [3, 8], [200, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const labelOpacity = interpolate(frame, [3, 5], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Green glow flash on impact
  const glowIntensity = interpolate(frame, [7, 8, 18], [0, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Subtitle fades up slightly delayed
  const subtitleOpacity = interpolate(frame, [12, 18], [0, 0.7], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const subtitleY = interpolate(frame, [12, 18], [10, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Decorative line under label
  const lineWidth = interpolate(frame, [8, 16], [0, 120], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Fade out to black at end
  const fadeOut = interpolate(
    frame,
    [durationInFrames - fadeFrames, durationInFrames],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <AbsoluteFill style={{ backgroundColor: colors.bg }}>
      <ScanLines />

      <AbsoluteFill
        style={{
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          alignItems: "center",
          gap: 20,
          zIndex: 1,
        }}
      >
        {/* Phase label */}
        <div
          style={{
            fontSize: 80,
            fontWeight: 700,
            fontFamily: fonts.mono,
            color: colors.teal,
            letterSpacing: 10,
            opacity: labelOpacity,
            transform: `translateX(${labelX}px)`,
            textShadow: `0 0 ${30 * glowIntensity}px ${colors.tealGlow}, 0 0 ${60 * glowIntensity}px ${colors.tealGlow}`,
          }}
        >
          {label}
        </div>

        {/* Decorative line */}
        <div
          style={{
            width: lineWidth,
            height: 1,
            backgroundColor: colors.teal,
            opacity: 0.4,
            boxShadow: `0 0 6px ${colors.teal}`,
          }}
        />

        {/* Subtitle */}
        <div
          style={{
            fontSize: 22,
            fontFamily: fonts.mono,
            color: colors.textMuted,
            opacity: subtitleOpacity,
            transform: `translateY(${subtitleY}px)`,
          }}
        >
          {subtitle}
        </div>
      </AbsoluteFill>

      {/* Fade to black */}
      <AbsoluteFill
        style={{
          backgroundColor: colors.bg,
          opacity: fadeOut,
          zIndex: 2,
        }}
      />
    </AbsoluteFill>
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
    subtitle: "Strategy goes live — scanning markets in real time",
  },
] as const;
