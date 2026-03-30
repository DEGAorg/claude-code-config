/** Terminal-aesthetic theme constants for Canon demo video */

export const colors = {
  bg: "#0d1117",
  bgLight: "#161b22",
  border: "#30363d",
  text: "#c9d1d9",
  textMuted: "#8b949e",
  green: "#3fb950",
  cyan: "#58a6ff",
  orange: "#d29922",
  purple: "#bc8cff",
  red: "#f85149",
  cursor: "#58a6ff",
} as const;

export const fonts = {
  mono: "JetBrains Mono, SF Mono, Menlo, monospace",
} as const;

export const sizing = {
  width: 1920,
  height: 1080,
  fps: 30,
} as const;

/** Timing in frames (at 30fps) */
export const timing = {
  introFrames: 120,
  phaseCardFrames: 90,
  outroFrames: 90,
  fadeFrames: 15,
  typeDelayFrames: 2,
} as const;
