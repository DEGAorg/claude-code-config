import { AbsoluteFill, useCurrentFrame, interpolate } from "remotion";
import { colors } from "../styles/theme";

interface GridBackgroundProps {
  /** Grid cell size in pixels */
  cellSize?: number;
  /** Animate a pulse that radiates from center */
  pulse?: boolean;
  /** Frame to trigger the pulse */
  pulseFrame?: number;
}

/**
 * Subtle perspective grid that recedes into the background.
 * Optional pulse effect radiates outward on a trigger frame.
 */
export const GridBackground: React.FC<GridBackgroundProps> = ({
  cellSize = 60,
  pulse = false,
  pulseFrame = 0,
}) => {
  const frame = useCurrentFrame();

  const pulseOpacity = pulse
    ? interpolate(
        frame,
        [pulseFrame, pulseFrame + 5, pulseFrame + 25],
        [0, 0.3, 0],
        { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
      )
    : 0;

  const pulseScale = pulse
    ? interpolate(frame, [pulseFrame, pulseFrame + 25], [0.2, 2.5], {
        extrapolateLeft: "clamp",
        extrapolateRight: "clamp",
      })
    : 0;

  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      {/* Static grid */}
      <svg width="100%" height="100%" style={{ opacity: 0.15 }}>
        <defs>
          <pattern
            id="grid"
            width={cellSize}
            height={cellSize}
            patternUnits="userSpaceOnUse"
          >
            <path
              d={`M ${cellSize} 0 L 0 0 0 ${cellSize}`}
              fill="none"
              stroke={colors.grid}
              strokeWidth="0.5"
            />
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill="url(#grid)" />
      </svg>

      {/* Pulse ring */}
      {pulse && pulseOpacity > 0 && (
        <AbsoluteFill
          style={{
            display: "flex",
            justifyContent: "center",
            alignItems: "center",
          }}
        >
          <div
            style={{
              width: 400,
              height: 400,
              borderRadius: "50%",
              border: `1px solid ${colors.green}`,
              opacity: pulseOpacity,
              transform: `scale(${pulseScale})`,
            }}
          />
        </AbsoluteFill>
      )}
    </AbsoluteFill>
  );
};
