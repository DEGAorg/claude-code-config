/** Canon demo video — Mr. Robot meets crypto dashboard */

export const colors = {
  bg: "#0a0a0a",
  bgSubtle: "#111111",
  grid: "#1a1a1a",
  gridBright: "#222222",
  border: "#2a2a2a",
  text: "#e8e8e8",
  textMuted: "#555555",
  green: "#00ff41",
  greenDim: "#00cc33",
  greenGlow: "rgba(0, 255, 65, 0.15)",
  blue: "#00d4ff",
  blueDim: "#0099cc",
  blueGlow: "rgba(0, 212, 255, 0.12)",
  scanLine: "rgba(0, 255, 65, 0.03)",
  cursor: "#00ff41",
} as const;

export const fonts = {
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
