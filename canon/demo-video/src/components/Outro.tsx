import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Terminal } from "./Terminal";
import { GlowText } from "./GlowText";
import { DataStream } from "./DataStream";
import { HorizontalRule } from "./HorizontalRule";
import { colors, fonts, timing } from "../styles/theme";

/**
 * Outro — closing card.
 *
 * Sequence:
 * 0-10:  Black, data streams fade in
 * 10-30: Tagline glows in
 * 35:    Line draws
 * 45:    Stats appear
 * 80:    GitHub link fades in
 * Last 15: Everything fades out
 */
export const Outro: React.FC = () => {
  const frame = useCurrentFrame();
  const { outroFrames } = timing;

  const streamOpacity = interpolate(frame, [0, 15], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const statsOpacity = interpolate(frame, [45, 55], [0, 0.7], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const linkOpacity = interpolate(frame, [80, 90], [0, 0.5], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const fadeOut = interpolate(
    frame,
    [outroFrames - 15, outroFrames],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <AbsoluteFill style={{ opacity: fadeOut }}>
      <Terminal>
        <AbsoluteFill style={{ opacity: streamOpacity }}>
          <DataStream columns={10} speed={0.4} opacity={0.04} />
        </AbsoluteFill>

        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 24,
            zIndex: 2,
          }}
        >
          <GlowText
            text="Agents build. You decide."
            fontSize={64}
            color={colors.green}
            glowColor={colors.greenGlow}
            enterFrame={10}
            stagger={1}
            spacing={2}
          />

          <HorizontalRule enterFrame={35} width={25} color={colors.blue} />

          {/* Stats line */}
          <div
            style={{
              display: "flex",
              gap: 40,
              opacity: statsOpacity,
              fontFamily: fonts.mono,
              fontSize: 16,
              color: colors.textMuted,
            }}
          >
            <span>
              agents <span style={{ color: colors.blue }}>+</span> skills{" "}
              <span style={{ color: colors.blue }}>+</span> strategies
            </span>
            <span style={{ color: colors.green }}>
              no code knowledge required
            </span>
          </div>

          {/* GitHub link */}
          <div
            style={{
              marginTop: 40,
              opacity: linkOpacity,
              fontFamily: fonts.mono,
              fontSize: 14,
              color: colors.blue,
              letterSpacing: 2,
            }}
          >
            github.com/DEGAorg
          </div>

          {/* Powered by */}
          <div
            style={{
              opacity: linkOpacity,
              fontFamily: fonts.mono,
              fontSize: 12,
              color: colors.textMuted,
              letterSpacing: 3,
              textTransform: "uppercase",
            }}
          >
            powered by DEGA
          </div>
        </div>
      </Terminal>
    </AbsoluteFill>
  );
};
