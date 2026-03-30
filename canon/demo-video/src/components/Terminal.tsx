import type React from "react";
import { colors, fonts } from "../styles/theme";

interface TerminalProps {
  title?: string;
  children: React.ReactNode;
}

/** Full-screen terminal window with title bar and dark background */
export const Terminal: React.FC<TerminalProps> = ({ title, children }) => {
  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        backgroundColor: colors.bg,
        fontFamily: fonts.mono,
        color: colors.text,
        display: "flex",
        flexDirection: "column",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 8,
          padding: "12px 16px",
          backgroundColor: colors.bgLight,
          borderBottom: `1px solid ${colors.border}`,
        }}
      >
        <div style={{ display: "flex", gap: 8 }}>
          <div
            style={{
              width: 12,
              height: 12,
              borderRadius: "50%",
              backgroundColor: colors.red,
            }}
          />
          <div
            style={{
              width: 12,
              height: 12,
              borderRadius: "50%",
              backgroundColor: colors.orange,
            }}
          />
          <div
            style={{
              width: 12,
              height: 12,
              borderRadius: "50%",
              backgroundColor: colors.green,
            }}
          />
        </div>
        {title && (
          <span
            style={{
              fontSize: 14,
              color: colors.textMuted,
              marginLeft: 8,
            }}
          >
            {title}
          </span>
        )}
      </div>
      <div
        style={{
          flex: 1,
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          alignItems: "center",
          padding: 48,
        }}
      >
        {children}
      </div>
    </div>
  );
};
