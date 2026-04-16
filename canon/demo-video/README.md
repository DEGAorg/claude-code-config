# Remotion video

<p align="center">
  <a href="https://github.com/remotion-dev/logo">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://github.com/remotion-dev/logo/raw/main/animated-logo-banner-dark.apng">
      <img alt="Animated Remotion Logo" src="https://github.com/remotion-dev/logo/raw/main/animated-logo-banner-light.gif">
    </picture>
  </a>
</p>

Welcome to your Remotion project!

## Commands

**Install Dependencies**

```console
pnpm i
```

**Start Preview**

```console
pnpm run dev
```

**Render video**

```console
pnpm exec remotion render
```

**Upgrade Remotion**

```console
pnpm exec remotion upgrade
```

## Workshop banners

Each workshop gets a YouTube Live thumbnail (1280x720 PNG). All banners
use the same layout so the series looks consistent.

### Creating a new banner

1. Copy `src/Workshop2Banner.tsx` to `src/Workshop<N>Banner.tsx`.
2. Change only these strings:
   - Workshop number: `Workshop 2` → `Workshop <N>`
   - Workshop title: `Canon Setup` → new title
   - Date line: `APRIL 14TH | 10:00 AM ET` → new date/time
3. Register in `src/Root.tsx`:
   ```tsx
   import { Workshop<N>Banner } from "./Workshop<N>Banner";
   // ...
   <Still
     id="Workshop<N>Banner"
     component={Workshop<N>Banner}
     width={1280}
     height={720}
   />
   ```
4. Render:
   ```bash
   pnpm exec remotion still Workshop<N>Banner out/workshop-<n>-banner.png
   ```

### Workshop schedule

| # | Title | Date |
|---|-------|------|
| 1 | Prediction Markets & NBA Playoffs Overview | Apr 9 |
| 2 | Canon Setup | Apr 14 |
| 3 | TBD | Apr 17 |
| 4 | TBD | Apr 22 |
| 5 | TBD | Apr 24 |

### What NOT to change

- Layout, spacing, fonts, colors, orbs, grid, or bottom bar
- Logo size/position
- Composition dimensions (1280x720)
