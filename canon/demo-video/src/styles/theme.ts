/** Canon unified theme — cyberpunk terminal aesthetic */

export const colors = {
  bg: "#000000",
  bgSubtle: "#0a0a0a",
  surface: "#111111",
  panel: "#151515",
  border: "#2a2a2a",
  text: "#ffffff",
  textMuted: "#a0a0a0",
  teal: "#00fffc",
  purple: "#7f00ff",
  gold: "#cfaa01",
  pink: "#ff007f",
  tealGlow: "rgba(0, 255, 252, 0.15)",
  purpleGlow: "rgba(127, 0, 255, 0.12)",
  pinkGlow: "rgba(255, 0, 127, 0.10)",
  scanLine: "rgba(0, 255, 252, 0.03)",
  cursor: "#00fffc",
} as const;

export const fonts = {
  heading: "Orbitron, sans-serif",
  subheading: "Rajdhani, sans-serif",
  body: "Space Grotesk, sans-serif",
  mono: "JetBrains Mono, SF Mono, Menlo, Consolas, monospace",
} as const;

export const sizing = {
  width: 1920,
  height: 1080,
  fps: 30,
} as const;

/** Timing in frames (at 30fps). Snappy for 2-3min hackathon demo. */
export const timing = {
  introFrames: 195,
  phaseCardFrames: 90,
  outroFrames: 165,
  fadeFrames: 10,
  typeDelayFrames: 1,
} as const;
