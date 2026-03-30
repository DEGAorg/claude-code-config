import { AbsoluteFill, useCurrentFrame } from "remotion";
import { colors } from "../styles/theme";

/**
 * CRT-style horizontal scan lines that drift slowly downward.
 * Subtle — adds texture without distracting from content.
 */
export const ScanLines: React.FC = () => {
  const frame = useCurrentFrame();
  const offset = (frame * 0.5) % 4;

  return (
    <AbsoluteFill style={{ pointerEvents: "none", opacity: 0.4 }}>
      <svg width="100%" height="100%">
        <defs>
          <pattern
            id="scanlines"
            width="100%"
            height="4"
            patternUnits="userSpaceOnUse"
            patternTransform={`translate(0, ${offset})`}
          >
            <line
              x1="0"
              y1="0"
              x2="100%"
              y2="0"
              stroke={colors.scanLine}
              strokeWidth="1"
            />
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill="url(#scanlines)" />
      </svg>
    </AbsoluteFill>
  );
};
