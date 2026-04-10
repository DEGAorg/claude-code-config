import { interpolate, useCurrentFrame } from "remotion";
import { colors, fonts } from "../styles/theme";

interface GlowTextProps {
  text: string;
  fontSize?: number;
  color?: string;
  glowColor?: string;
  /** Frame when the text starts appearing */
  enterFrame?: number;
  /** Stagger each character by N frames */
  stagger?: number;
  /** Letter spacing */
  spacing?: number;
}

/**
 * Text where each character fades in with a glow bloom effect,
 * staggered left-to-right. The glow pulses then settles.
 */
export const GlowText: React.FC<GlowTextProps> = ({
  text,
  fontSize = 72,
  color = colors.teal,
  glowColor = colors.tealGlow,
  enterFrame = 0,
  stagger = 2,
  spacing = 4,
}) => {
  const frame = useCurrentFrame();

  return (
    <div
      style={{
        display: "flex",
        justifyContent: "center",
        fontFamily: fonts.mono,
        fontSize,
        fontWeight: 700,
        letterSpacing: spacing,
      }}
    >
      {text.split("").map((char, i) => {
        const charEnter = enterFrame + i * stagger;
        const elapsed = frame - charEnter;

        const charOpacity = interpolate(elapsed, [0, 4], [0, 1], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        });

        const glowIntensity = interpolate(elapsed, [0, 4, 15], [0, 1, 0.2], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        });

        const yOffset = interpolate(elapsed, [0, 6], [8, 0], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        });

        return (
          <span
            key={i}
            style={{
              opacity: charOpacity,
              color,
              transform: `translateY(${yOffset}px)`,
              textShadow: `0 0 ${20 * glowIntensity}px ${glowColor}, 0 0 ${40 * glowIntensity}px ${glowColor}`,
              display: "inline-block",
              minWidth: char === " " ? "0.3em" : undefined,
            }}
          >
            {char}
          </span>
        );
      })}
    </div>
  );
};
