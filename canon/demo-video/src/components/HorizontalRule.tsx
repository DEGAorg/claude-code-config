import { interpolate, useCurrentFrame } from "remotion";
import { colors } from "../styles/theme";

interface HorizontalRuleProps {
  /** Frame when the line starts drawing */
  enterFrame?: number;
  /** Width of the line as percentage */
  width?: number;
  color?: string;
}

/**
 * Animated horizontal line that draws from center outward.
 * Used as a separator between title and subtitle.
 */
export const HorizontalRule: React.FC<HorizontalRuleProps> = ({
  enterFrame = 0,
  width = 40,
  color = colors.teal,
}) => {
  const frame = useCurrentFrame();
  const elapsed = frame - enterFrame;

  const lineWidth = interpolate(elapsed, [0, 10], [0, width], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const lineOpacity = interpolate(elapsed, [0, 3], [0, 0.6], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <div
      style={{
        width: "100%",
        display: "flex",
        justifyContent: "center",
        opacity: lineOpacity,
      }}
    >
      <div
        style={{
          width: `${lineWidth}%`,
          height: 1,
          backgroundColor: color,
          boxShadow: `0 0 8px ${color}`,
        }}
      />
    </div>
  );
};
