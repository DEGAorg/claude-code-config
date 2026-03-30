import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Terminal } from "./components/Terminal";
import { TypeWriter } from "./components/TypeWriter";
import { colors, fonts, timing } from "./styles/theme";

/**
 * Intro composition — DEGA logo, tagline with typed-text
 * cursor animation, and fade to black.
 * Duration: timing.introFrames (120 frames / 4s at 30fps)
 */
export const Intro: React.FC = () => {
  const frame = useCurrentFrame();

  const logoOpacity = interpolate(frame, [10, 30], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const fadeToBlack = interpolate(
    frame,
    [timing.introFrames - timing.fadeFrames, timing.introFrames],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <AbsoluteFill>
      <Terminal title="canon — intro">
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 32,
          }}
        >
          <div
            style={{
              opacity: logoOpacity,
              fontFamily: fonts.mono,
              fontSize: 96,
              fontWeight: 700,
              color: colors.green,
              letterSpacing: 12,
            }}
          >
            DEGA
          </div>

          <TypeWriter
            text="Canon — AI builds prediction market strategies"
            startFrame={35}
            fontSize={28}
            color={colors.textMuted}
          />
        </div>
      </Terminal>

      {/* Fade to black overlay */}
      <AbsoluteFill
        style={{
          backgroundColor: "black",
          opacity: fadeToBlack,
        }}
      />
    </AbsoluteFill>
  );
};
