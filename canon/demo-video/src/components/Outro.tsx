import { interpolate, useCurrentFrame } from "remotion";
import { Terminal } from "./Terminal";
import { TypeWriter } from "./TypeWriter";
import { colors, timing } from "../styles/theme";

/** Outro composition — tagline, branding, fade to black */
export const Outro: React.FC = () => {
  const frame = useCurrentFrame();
  const { outroFrames, fadeFrames } = timing;

  const fadeOutOpacity = interpolate(
    frame,
    [outroFrames - fadeFrames, outroFrames],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  const brandingOpacity = interpolate(
    frame,
    [20, 35],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <div style={{ width: "100%", height: "100%", opacity: fadeOutOpacity }}>
      <Terminal>
        <TypeWriter
          text="Ship faster with agents."
          fontSize={52}
          color={colors.green}
          startFrame={5}
          delayFrames={2}
          showCursor={false}
        />
        <div
          style={{
            opacity: brandingOpacity,
            marginTop: 40,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 12,
          }}
        >
          <span
            style={{
              fontSize: 28,
              color: colors.textMuted,
              fontFamily: "JetBrains Mono, SF Mono, Menlo, monospace",
            }}
          >
            DEGA — Canon Pipeline
          </span>
          <span
            style={{
              fontSize: 18,
              color: colors.cyan,
              fontFamily: "JetBrains Mono, SF Mono, Menlo, monospace",
            }}
          >
            github.com/DEGAorg
          </span>
        </div>
      </Terminal>
    </div>
  );
};
