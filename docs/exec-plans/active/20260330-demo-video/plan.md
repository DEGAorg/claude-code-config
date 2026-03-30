# Plan: Canon Demo Video — Remotion Intro & Transitions

## Context

The canon demo is a screen recording of the full pipeline (scaffold →
strategy → develop → run). The recording itself is slow and needs visual
structure: an intro, phase transition cards, and an outro. These are
built with Remotion (React-based programmatic video) and composited
with the screen recording in post.

Location: `canon/demo-video/`

## Video segments

The Remotion project produces standalone video clips that get spliced
into the screen recording. Each segment is a Remotion composition.

### 1. Intro (5-8s)

- DEGA logo fade-in (or text "DEGA" in monospace)
- Tagline: "Canon — AI builds prediction market strategies"
- Subtle terminal-style animation (blinking cursor, typed text effect)
- Dark background, green/white terminal palette
- Fade to black at end

### 2. Phase: Scaffold (2-3s)

Title card between intro and scaffold recording:

- Phase label: "SCAFFOLD"
- Subtitle: "Fetching agents, skills, and project structure"
- Phase number indicator: "1 / 5"
- Slide-in from right or glitch/reveal animation
- Terminal aesthetic consistent with intro

### 3. Phase: Strategy (2-3s)

- Phase label: "STRATEGY"
- Subtitle: "Selecting market and designing the edge"
- Phase number: "2 / 5"

### 4. Phase: Develop (2-3s)

- Phase label: "BUILD"
- Subtitle: "Orchestrator drives workers to implement the strategy"
- Phase number: "3 / 5"

### 5. Phase: Test & Review (2-3s)

- Phase label: "REVIEW"
- Subtitle: "Automated review — iterate until SHIP"
- Phase number: "4 / 5"

### 6. Phase: Run (2-3s)

- Phase label: "RUN"
- Subtitle: "Strategy live — scanning markets, detecting edges"
- Phase number: "5 / 5"

### 7. Outro (4-6s)

- Summary stats (could be dynamic props):
  - "6 agents — 8 skills — 1 strategy — 0 human code"
- DEGA branding
- URL or GitHub link
- Fade out

## Technical approach

### Stack

- Remotion 4.x (latest stable)
- TypeScript, React
- Tailwind CSS (via `@remotion/tailwind`) for styling
- `@remotion/transitions` for slide/fade effects

### Project structure

```
canon/demo-video/
├── package.json
├── tsconfig.json
├── remotion.config.ts
├── src/
│   ├── Root.tsx              # Composition registry
│   ├── Intro.tsx             # Intro segment
│   ├── PhaseCard.tsx         # Reusable phase transition component
│   ├── Outro.tsx             # Outro segment
│   ├── components/
│   │   ├── Terminal.tsx      # Terminal-style text container
│   │   ├── TypeWriter.tsx    # Typed text animation
│   │   └── PhaseCounter.tsx  # "N / 5" indicator
│   └── styles/
│       └── theme.ts          # Colors, fonts, timing constants
└── public/
    └── fonts/                # Monospace font (JetBrains Mono or similar)
```

### Output

- Resolution: 1920x1080 (matches screen recording)
- FPS: 30
- Format: MP4 (H.264) for each composition
- Also exports individual segments for flexible compositing

### Design system

- Background: `#0a0a0a` (near-black)
- Primary text: `#e0e0e0` (light gray)
- Accent: `#22c55e` (green-500, terminal green)
- Secondary accent: `#3b82f6` (blue-500, for phase numbers)
- Font: JetBrains Mono (monospace, terminal feel)
- All animations ease-in-out, no jarring cuts

## Progress log

- [ ] Scaffold Remotion project in `canon/demo-video/` — init with `pnpm create video`, configure TS + Tailwind
- [ ] Create theme and shared components — Terminal, TypeWriter, PhaseCounter (deps: 1)
- [ ] Build Intro composition — logo, tagline, cursor animation (deps: 2)
- [ ] Build PhaseCard composition — reusable for all 5 phases, accepts props (label, subtitle, number) (deps: 2)
- [ ] Build Outro composition — stats, branding, fade (deps: 2)
- [ ] Wire all compositions in Root.tsx, render previews, verify timing (deps: 3, 4, 5)
- [ ] Export all segments as MP4 clips (deps: 6)

## Completion criteria

- [ ] `pnpm exec remotion preview` shows all compositions
- [ ] Each phase card renders with correct label, subtitle, and counter
- [ ] Intro has typed-text animation and terminal aesthetic
- [ ] Outro shows dynamic stats
- [ ] All segments export to MP4 at 1920x1080 30fps
- [ ] Total Remotion content under 30s (clips are concise)
