import "./index.css";
import { AbsoluteFill, Composition, Series, Still } from "remotion";
import { HackathonBanner } from "./HackathonBanner";
import { Workshop1Banner } from "./Workshop1Banner";
import { Intro } from "./Intro";
import { PhaseCard, phases } from "./PhaseCard";
import { Outro } from "./components/Outro";
import { colors, sizing, timing } from "./styles/theme";

const { width, height, fps } = sizing;
const { introFrames, phaseCardFrames, outroFrames } = timing;
const totalFrames =
  introFrames + phases.length * phaseCardFrames + outroFrames;

/** Full demo video — all segments sequenced via Series */
const FullDemo: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: colors.bg }}>
      <Series>
        <Series.Sequence durationInFrames={introFrames}>
        <Intro />
      </Series.Sequence>
      {phases.map((phase) => (
        <Series.Sequence
          key={phase.id}
          durationInFrames={phaseCardFrames}
        >
          <PhaseCard label={phase.label} subtitle={phase.subtitle} />
        </Series.Sequence>
      ))}
      <Series.Sequence durationInFrames={outroFrames}>
        <Outro />
      </Series.Sequence>
      </Series>
    </AbsoluteFill>
  );
};

export const RemotionRoot: React.FC = () => {
  return (
    <>
      {/* Full sequenced video */}
      <Composition
        id="FullDemo"
        component={FullDemo}
        durationInFrames={totalFrames}
        fps={fps}
        width={width}
        height={height}
      />

      {/* Individual compositions for previewing segments */}
      <Composition
        id="Intro"
        component={Intro}
        durationInFrames={introFrames}
        fps={fps}
        width={width}
        height={height}
      />

      {phases.map((phase) => (
        <Composition
          key={phase.id}
          id={`Phase-${phase.id}`}
          component={() => (
            <PhaseCard label={phase.label} subtitle={phase.subtitle} />
          )}
          durationInFrames={phaseCardFrames}
          fps={fps}
          width={width}
          height={height}
        />
      ))}

      <Composition
        id="Outro"
        component={Outro}
        durationInFrames={outroFrames}
        fps={fps}
        width={width}
        height={height}
      />

      {/* Hackathon banner — 2400×1200 still */}
      <Still
        id="HackathonBanner"
        component={HackathonBanner}
        width={2400}
        height={1200}
      />

      {/* Workshop 1 YouTube thumbnail — 1280×720 still */}
      <Still
        id="Workshop1Banner"
        component={Workshop1Banner}
        width={1280}
        height={720}
      />
    </>
  );
};
