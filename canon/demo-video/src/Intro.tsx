import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Terminal } from "./components/Terminal";
import { GlowText } from "./components/GlowText";
import { TypeWriter } from "./components/TypeWriter";
import { DataStream } from "./components/DataStream";
import { HorizontalRule } from "./components/HorizontalRule";
import { colors, fonts, timing } from "./styles/theme";

/**
 * Intro — Canon title reveal.
 *
 * Sequence:
 * 0-15:  Black, data streams fade in at edges
 * 15-35: "CANON" glows in character by character
 * 40-50: Horizontal rule draws from center
 * 50+:   Tagline types out below
 * 120+:  "powered by DEGA" fades in
 * Last 8 frames: fade to black
 */
export const Intro: React.FC = () => {
  const frame = useCurrentFrame();

  const streamOpacity = interpolate(frame, [0, 20], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const degaOpacity = interpolate(frame, [115, 130], [0, 0.5], {
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
      <Terminal pulseFrame={15}>
        {/* Data streams in the margins */}
        <AbsoluteFill style={{ opacity: streamOpacity }}>
          <DataStream columns={14} speed={0.8} opacity={0.06} />
        </AbsoluteFill>

        {/* Main content */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 28,
            zIndex: 2,
          }}
        >
          <GlowText
            text="CANON"
            fontSize={120}
            color={colors.teal}
            glowColor={colors.tealGlow}
            enterFrame={15}
            stagger={3}
            spacing={16}
          />

          <HorizontalRule enterFrame={40} width={30} color={colors.teal} />

          <TypeWriter
            text="AI-powered prediction market strategy"
            startFrame={50}
            fontSize={26}
            color={colors.textMuted}
            delayFrames={1}
            showCursor={true}
          />

          {/* Powered by DEGA — small footer credit */}
          <div
            style={{
              marginTop: 60,
              opacity: degaOpacity,
              fontFamily: fonts.mono,
              fontSize: 14,
              color: colors.textMuted,
              letterSpacing: 4,
              textTransform: "uppercase",
            }}
          >
            powered by DEGA
          </div>
        </div>
      </Terminal>

      {/* Fade to black */}
      <AbsoluteFill
        style={{
          backgroundColor: colors.bg,
          opacity: fadeToBlack,
        }}
      />
    </AbsoluteFill>
  );
};
