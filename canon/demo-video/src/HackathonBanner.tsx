import { AbsoluteFill, staticFile } from "remotion";

const theme = {
  bg: "#000000",
  teal: "#00fffc",
  purple: "#7f00ff",
  gold: "#cfaa01",
  pink: "#ff007f",
  white: "#ffffff",
  muted: "#8b949e",
  border: "#2a2a2a",
} as const;

const font = {
  heading: "Orbitron, sans-serif",
  sub: "Rajdhani, sans-serif",
  body: "Space Grotesk, sans-serif",
  mono: "JetBrains Mono, monospace",
} as const;

/** Grid overlay — subtle purple lines */
const GridOverlay: React.FC = () => (
  <AbsoluteFill
    style={{
      backgroundImage: `
        linear-gradient(${theme.purple}0d 1px, transparent 1px),
        linear-gradient(90deg, ${theme.purple}0d 1px, transparent 1px)
      `,
      backgroundSize: "50px 50px",
    }}
  />
);

/** Floating blurred orb */
const Orb: React.FC<{
  color: string;
  size: number;
  top: string;
  left: string;
}> = ({ color, size, top, left }) => (
  <div
    style={{
      position: "absolute",
      top,
      left,
      width: size,
      height: size,
      borderRadius: "50%",
      background: `radial-gradient(circle, ${color}40 0%, transparent 70%)`,
      filter: "blur(80px)",
    }}
  />
);

/** Static hackathon banner — 2400×1200 still */
export const HackathonBanner: React.FC = () => {
  return (
    <AbsoluteFill
      style={{
        backgroundColor: theme.bg,
        fontFamily: font.body,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <GridOverlay />

      {/* Background orbs */}
      <Orb color={theme.purple} size={600} top="5%" left="10%" />
      <Orb color={theme.teal} size={500} top="40%" left="65%" />
      <Orb color={theme.pink} size={400} top="60%" left="25%" />

      {/* DEGA logo — top left */}
      <img
        src={staticFile("dega-logo.png")}
        alt="DEGA"
        style={{
          position: "absolute",
          top: 50,
          left: 60,
          width: 220,
          objectFit: "contain",
          zIndex: 2,
        }}
      />

      {/* Content layer */}
      <div
        style={{
          position: "relative",
          zIndex: 1,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 40,
          padding: "0 120px",
        }}
      >
        {/* Main headline */}
        <div
          style={{
            fontFamily: font.heading,
            fontSize: 72,
            fontWeight: 900,
            color: theme.teal,
            textTransform: "uppercase",
            letterSpacing: 6,
            textAlign: "center",
            lineHeight: 1.2,
            textShadow: `0 0 60px ${theme.teal}80, 0 0 120px ${theme.teal}40`,
          }}
        >
          NBA Playoffs Prediction
          <br />
          Market Hackathon
        </div>

        {/* Subheadline */}
        <div
          style={{
            fontFamily: font.sub,
            fontSize: 40,
            fontWeight: 300,
            color: theme.white,
            textAlign: "center",
            letterSpacing: 2,
          }}
        >
          Build AI trading automations for prediction markets
        </div>

        {/* Separator */}
        <div
          style={{
            width: 800,
            height: 1,
            backgroundColor: theme.border,
          }}
        />

        {/* Key details row */}
        <div
          style={{
            display: "flex",
            gap: 100,
            alignItems: "center",
          }}
        >
          <div
            style={{
              fontFamily: font.body,
              fontSize: 36,
              fontWeight: 700,
              color: theme.gold,
              letterSpacing: 3,
            }}
          >
            $1,000 PRIZE
          </div>
          <div
            style={{
              fontFamily: font.body,
              fontSize: 36,
              fontWeight: 700,
              color: theme.teal,
              letterSpacing: 3,
            }}
          >
            FREE WORKSHOPS
          </div>
          <div
            style={{
              fontFamily: font.body,
              fontSize: 36,
              fontWeight: 700,
              color: theme.white,
              letterSpacing: 3,
            }}
          >
            NO EXPERIENCE NEEDED
          </div>
        </div>

        {/* Dates */}
        <div
          style={{
            fontFamily: font.body,
            fontSize: 28,
            color: theme.muted,
            letterSpacing: 1,
          }}
        >
          Workshops start April 9th | Registration opens May 4th
        </div>

        {/* Separator */}
        <div
          style={{
            width: 400,
            height: 1,
            backgroundColor: theme.border,
          }}
        />

        {/* Powered by Canon */}
        <div
          style={{
            fontFamily: font.mono,
            fontSize: 24,
            color: theme.muted,
            letterSpacing: 1,
          }}
        >
          {">"} canon init my-strategy{" "}
          <span style={{ color: theme.teal }}>_</span>
        </div>
      </div>
    </AbsoluteFill>
  );
};
