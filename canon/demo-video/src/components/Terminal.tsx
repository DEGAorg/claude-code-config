import type React from "react";
import { AbsoluteFill } from "remotion";
import { colors, fonts } from "../styles/theme";
import { ScanLines } from "./ScanLines";
import { GridBackground } from "./GridBackground";

interface TerminalProps {
  children: React.ReactNode;
  /** Show the background grid */
  grid?: boolean;
  /** Grid pulse on a specific frame */
  pulseFrame?: number;
}

/** Full-screen dark canvas with optional scan lines and grid. */
export const Terminal: React.FC<TerminalProps> = ({
  children,
  grid = true,
  pulseFrame,
}) => {
  return (
    <AbsoluteFill
      style={{
        backgroundColor: colors.bg,
        fontFamily: fonts.mono,
        color: colors.text,
      }}
    >
      {grid && (
        <GridBackground
          pulse={pulseFrame !== undefined}
          pulseFrame={pulseFrame}
        />
      )}
      <ScanLines />
      <AbsoluteFill
        style={{
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          alignItems: "center",
          padding: 80,
          zIndex: 1,
        }}
      >
        {children}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
