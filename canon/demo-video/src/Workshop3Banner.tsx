import { AbsoluteFill, staticFile } from "remotion";

const theme = {
  bg: "#000000",
  teal: "#00fffc",
  purple: "#7f00ff",
  gold: "#cfaa01",
  white: "#ffffff",
  muted: "#a0a0a0",
  border: "#2a2a2a",
} as const;

const font = {
  heading: "Orbitron, sans-serif",
  sub: "Rajdhani, sans-serif",
  body: "Space Grotesk, sans-serif",
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

/** Workshop 3 YouTube thumbnail — 1280×720 still */
export const Workshop3Banner: React.FC = () => {
  return (
    <AbsoluteFill
      style={{
        backgroundColor: theme.bg,
        fontFamily: font.body,
      }}
    >
      <GridOverlay />

      {/* Background orbs */}
      <Orb color={theme.purple} size={500} top="-10%" left="-5%" />
      <Orb color={theme.teal} size={400} top="30%" left="60%" />

      {/* DEGA logo — top left */}
      <img
        src={staticFile("dega-logo.png")}
        alt="DEGA"
        style={{
          position: "absolute",
          top: 30,
          left: 40,
          width: 140,
          objectFit: "contain",
          zIndex: 2,
        }}
      />

      {/* Centered content */}
      <div
        style={{
          position: "relative",
          zIndex: 1,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          height: "100%",
          gap: 24,
          textAlign: "center",
        }}
      >
        {/* Series label */}
        <div
          style={{
            fontFamily: font.sub,
            fontSize: 22,
            fontWeight: 400,
            color: theme.muted,
            letterSpacing: 5,
            textTransform: "uppercase",
          }}
        >
          Canon Hackathon Workshop Series
        </div>

        {/* Workshop number */}
        <div
          style={{
            fontFamily: font.heading,
            fontSize: 72,
            fontWeight: 900,
            color: theme.teal,
            textTransform: "uppercase",
            letterSpacing: 6,
            textShadow: `0 0 40px ${theme.teal}80, 0 0 80px ${theme.teal}40`,
          }}
        >
          Workshop 3
        </div>

        {/* Workshop title */}
        <div
          style={{
            fontFamily: font.heading,
            fontSize: 36,
            fontWeight: 700,
            color: theme.white,
            textTransform: "uppercase",
            letterSpacing: 3,
            lineHeight: 1.4,
          }}
        >
          Running Your First
          <br />
          Strategy
        </div>

        {/* Date */}
        <div
          style={{
            fontFamily: font.body,
            fontSize: 30,
            fontWeight: 500,
            color: theme.gold,
            letterSpacing: 3,
            marginTop: 8,
          }}
        >
          APRIL 16TH | 10:00 AM ET
        </div>

        {/* Prize */}
        <div
          style={{
            fontFamily: font.heading,
            fontSize: 28,
            fontWeight: 700,
            color: theme.bg,
            backgroundColor: theme.gold,
            padding: "8px 32px",
            borderRadius: 6,
            letterSpacing: 3,
            marginTop: 4,
          }}
        >
          USD $1,000 PRIZE
        </div>
      </div>

      {/* Bottom bar */}
      <div
        style={{
          position: "absolute",
          bottom: 0,
          left: 0,
          right: 0,
          height: 50,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          borderTop: `1px solid ${theme.border}`,
          zIndex: 2,
        }}
      >
        <div
          style={{
            fontFamily: font.sub,
            fontSize: 16,
            color: theme.muted,
            letterSpacing: 6,
            textTransform: "uppercase",
          }}
        >
          NBA Playoffs Prediction Market Hackathon
        </div>
      </div>
    </AbsoluteFill>
  );
};
