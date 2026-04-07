/**
 * Focused tests for runner.ts exports:
 *   - normalize
 *   - textMentionsTeam
 *   - extractTeamOdds
 *
 * These cover the logic that was previously truncated/missing in runner.ts.
 */

import { describe, it, expect } from "vitest";
import { normalize, textMentionsTeam, extractTeamOdds } from "../runner.js";
import type { OddsEvent } from "../runner.js";

// ── normalize ────────────────────────────────────────────────────────────────

describe("normalize", () => {
  it("lowercases input and strips non-alphanumeric chars", () => {
    expect(normalize("Los Angeles Lakers!")).toBe("los angeles lakers");
  });

  it("preserves digits (e.g. 76ers)", () => {
    expect(normalize("76ers")).toBe("76ers");
  });

  it("trims leading and trailing whitespace", () => {
    expect(normalize("  Celtics  ")).toBe("celtics");
  });
});

// ── textMentionsTeam ─────────────────────────────────────────────────────────

describe("textMentionsTeam", () => {
  it("matches via direct substring (full team name)", () => {
    expect(
      textMentionsTeam(
        "Will the Boston Celtics win the 2026 NBA Finals?",
        "Boston Celtics",
      ),
    ).toBe(true);
  });

  it("matches via last-word fallback (short nickname)", () => {
    // 'Thunder' is the last word of 'Oklahoma City Thunder'
    expect(
      textMentionsTeam(
        "Will the Thunder win the championship?",
        "Oklahoma City Thunder",
      ),
    ).toBe(true);
  });

  it("matches via alias table for 76ers / Philadelphia", () => {
    // 'philadelphia' is an alias for '76ers' entry
    expect(
      textMentionsTeam(
        "Philadelphia 76ers championship odds",
        "Philadelphia 76ers",
      ),
    ).toBe(true);
  });

  it("returns false for unrelated team", () => {
    expect(
      textMentionsTeam(
        "Will the Lakers win the Finals?",
        "Boston Celtics",
      ),
    ).toBe(false);
  });
});

// ── extractTeamOdds ──────────────────────────────────────────────────────────

describe("extractTeamOdds", () => {
  it("computes average implied probability across bookmakers", () => {
    // Team A: dk=4.0 (25%), fd=5.0 (20%) → avg 22.5%
    const events: OddsEvent[] = [
      {
        id: "ev1",
        homeTeam: "",
        awayTeam: "",
        commence: new Date(),
        bookmakers: [
          {
            key: "dk",
            title: "DraftKings",
            markets: [
              {
                key: "outrights",
                outcomes: [{ name: "Team A", price: 4.0 }],
              },
            ],
          },
          {
            key: "fd",
            title: "FanDuel",
            markets: [
              {
                key: "outrights",
                outcomes: [{ name: "Team A", price: 5.0 }],
              },
            ],
          },
        ],
      },
    ];

    const result = extractTeamOdds(events);
    expect(result).toHaveLength(1);
    expect(result[0]?.team).toBe("Team A");
    // 1/4.0 = 0.25, 1/5.0 = 0.20 → avg = 0.225
    expect(result[0]?.impliedProb).toBeCloseTo(0.225, 3);
    expect(result[0]?.sources).toBe(2);
  });

  it("ignores non-outrights markets", () => {
    const events: OddsEvent[] = [
      {
        id: "ev2",
        homeTeam: "",
        awayTeam: "",
        commence: new Date(),
        bookmakers: [
          {
            key: "dk",
            title: "DraftKings",
            markets: [
              // h2h market should be ignored
              {
                key: "h2h",
                outcomes: [{ name: "Team B", price: 2.0 }],
              },
            ],
          },
        ],
      },
    ];

    // No outrights market → no results
    const result = extractTeamOdds(events);
    expect(result).toHaveLength(0);
  });

  it("aggregates multiple teams from a single event", () => {
    const events: OddsEvent[] = [
      {
        id: "ev3",
        homeTeam: "",
        awayTeam: "",
        commence: new Date(),
        bookmakers: [
          {
            key: "dk",
            title: "DraftKings",
            markets: [
              {
                key: "outrights",
                outcomes: [
                  { name: "Team X", price: 2.0 },  // 50%
                  { name: "Team Y", price: 4.0 },  // 25%
                ],
              },
            ],
          },
        ],
      },
    ];

    const result = extractTeamOdds(events);
    expect(result).toHaveLength(2);

    const teamX = result.find((r) => r.team === "Team X");
    const teamY = result.find((r) => r.team === "Team Y");

    expect(teamX?.impliedProb).toBeCloseTo(0.5, 3);
    expect(teamY?.impliedProb).toBeCloseTo(0.25, 3);
    expect(teamX?.sources).toBe(1);
    expect(teamY?.sources).toBe(1);
  });
});
