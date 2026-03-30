import { useCurrentFrame } from "remotion";
import { colors, fonts, timing } from "../styles/theme";

interface TypeWriterProps {
  text: string;
  /** Frame offset before typing starts (default: 0) */
  startFrame?: number;
  /** Frames between each character (default: timing.typeDelayFrames) */
  delayFrames?: number;
  fontSize?: number;
  color?: string;
  showCursor?: boolean;
}

/**
 * Animates text appearing character-by-character with
 * an optional blinking cursor.
 */
export const TypeWriter: React.FC<TypeWriterProps> = ({
  text,
  startFrame = 0,
  delayFrames = timing.typeDelayFrames,
  fontSize = 48,
  color = colors.text,
  showCursor = true,
}) => {
  const frame = useCurrentFrame();
  const elapsed = Math.max(0, frame - startFrame);
  const charsVisible = Math.min(
    text.length,
    Math.floor(elapsed / delayFrames),
  );
  const visibleText = text.slice(0, charsVisible);
  const typingDone = charsVisible >= text.length;
  const cursorVisible = showCursor && (!typingDone || frame % 30 < 15);

  return (
    <span
      style={{
        fontFamily: fonts.mono,
        fontSize,
        color,
        whiteSpace: "pre",
      }}
    >
      {visibleText}
      {cursorVisible && (
        <span style={{ color: colors.cursor }}>|</span>
      )}
    </span>
  );
};
