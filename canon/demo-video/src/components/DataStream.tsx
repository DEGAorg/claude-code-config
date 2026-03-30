import { AbsoluteFill, useCurrentFrame } from "remotion";
import { colors, fonts } from "../styles/theme";

interface DataStreamProps {
  /** Number of columns */
  columns?: number;
  /** Speed multiplier */
  speed?: number;
  /** Overall opacity */
  opacity?: number;
}

/**
 * Vertical streams of hex/numeric characters falling like a data feed.
 * Not full Matrix rain — sparse, elegant, in the margins.
 */
export const DataStream: React.FC<DataStreamProps> = ({
  columns = 12,
  speed = 1,
  opacity = 0.08,
}) => {
  const frame = useCurrentFrame();
  const chars = "0123456789abcdef";

  const seededRandom = (seed: number): number => {
    const x = Math.sin(seed * 127.1) * 43758.5453;
    return x - Math.floor(x);
  };

  const streamColumns = Array.from({ length: columns }, (_, col) => {
    const x = (col / columns) * 100;
    const colSpeed = speed * (0.5 + seededRandom(col) * 1.5);
    const startOffset = seededRandom(col + 100) * 200;

    const streamChars = Array.from({ length: 20 }, (_, row) => {
      const y =
        ((frame * colSpeed + startOffset + row * 30) % 1200) - 100;
      const charIndex =
        Math.floor(seededRandom(col * 100 + row * 7 + frame * 0.1) * chars.length);
      const charOpacity = interpolateLinear(y, 0, 1080, 0.6, 0.1);

      return { y, char: chars[charIndex], opacity: charOpacity, row };
    });

    return { x, chars: streamChars };
  });

  return (
    <AbsoluteFill style={{ pointerEvents: "none", opacity }}>
      {streamColumns.map((col, ci) =>
        col.chars.map((c) => (
          <span
            key={`${ci}-${c.row}`}
            style={{
              position: "absolute",
              left: `${col.x}%`,
              top: c.y,
              fontFamily: fonts.mono,
              fontSize: 11,
              color: colors.green,
              opacity: c.opacity,
            }}
          >
            {c.char}
          </span>
        )),
      )}
    </AbsoluteFill>
  );
};

function interpolateLinear(
  value: number,
  inMin: number,
  inMax: number,
  outMin: number,
  outMax: number,
): number {
  const t = Math.max(0, Math.min(1, (value - inMin) / (inMax - inMin)));
  return outMin + t * (outMax - outMin);
}
