import { AbsoluteFill } from "remotion";
import { GridBackground } from "./components/GridBackground";
import { ScanLines } from "./components/ScanLines";
import { DataStream } from "./components/DataStream";
import { colors, fonts } from "./styles/theme";

/**
 * Static thumbnail for the demo video.
 * Rendered as a single frame (still image).
 */
export const Thumbnail: React.FC = () => {
  return (
    <AbsoluteFill
      style={{
        backgroundColor: colors.bg,
        fontFamily: fonts.mono,
      }}
    >
      <GridBackground />
      <ScanLines />
      <AbsoluteFill style={{ opacity: 0.06 }}>
        <DataStream columns={14} speed={0} opacity={1} />
      </AbsoluteFill>

      <AbsoluteFill
        style={{
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          alignItems: "center",
          padding: 120,
          gap: 32,
          zIndex: 1,
        }}
      >
        {/* CANON logo */}
        <div
          style={{
            fontSize: 64,
            fontWeight: 700,
            color: colors.green,
            letterSpacing: 12,
            textShadow: `0 0 20px ${colors.greenGlow}, 0 0 40px ${colors.greenGlow}`,
          }}
        >
          CANON
        </div>

        {/* Separator */}
        <div
          style={{
            width: 200,
            height: 1,
            backgroundColor: colors.green,
            opacity: 0.4,
            boxShadow: `0 0 8px ${colors.green}`,
          }}
        />

        {/* Title */}
        <div
          style={{
            fontSize: 48,
            fontWeight: 700,
            color: colors.text,
            textAlign: "center",
            lineHeight: 1.3,
            maxWidth: 1200,
          }}
        >
          Prediction Market Strategy
        </div>
        <div
          style={{
            fontSize: 48,
            fontWeight: 700,
            color: colors.blue,
            textAlign: "center",
            textShadow: `0 0 15px ${colors.blueGlow}, 0 0 30px ${colors.blueGlow}`,
          }}
        >
          Built From Scratch by AI
        </div>

        {/* Footer */}
        <div
          style={{
            marginTop: 40,
            fontSize: 14,
            color: colors.textMuted,
            letterSpacing: 4,
            textTransform: "uppercase",
          }}
        >
          powered by DEGA
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
