# Strategy Design Specification: NBA Game Momentum Trader

**Archetype:** Momentum / Event-Driven
**Platform:** Polymarket
**Category:** Sports — NBA

---

## Target Markets

| Field | Value |
|-------|-------|
| Platform | Polymarket |
| Market type | NBA game winner (individual games) |
| Resolution | End of game (final score) |
| Liquidity | Moderate to high ($100K+ volume on marquee matchups) |
| Season | 2025-2026 NBA regular season and playoffs |

NBA game markets on Polymarket resolve at final whistle. Prices reflect
real-time win probability and move significantly on:
- Injury reports (pre-game and in-game)
- Lineup announcements (confirmed starters)
- Sharp line moves from sportsbooks (Vegas consensus shifts)
- Pre-game momentum (team streaks, rest days, travel schedule)

---

## Edge Analysis

**Thesis:** Pre-game injury news and lineup changes create temporary
mispricings in Polymarket NBA markets. When a key player (top-3 in
minutes for the team) is ruled out within 2 hours of tipoff, the market
adjusts slowly — sportsbooks move first, Polymarket lags by 10-30 minutes.

**Estimated edge:** 4-7% per trade on injury-driven moves.

**Why this market:**
- High frequency (82 games per team, 1230 regular season games total)
- Clear resolution (final score, no ambiguity)
- Predictable catalyst timing (injury reports released on schedule)
- Sportsbook lines provide reference pricing for fair value

---

## Entry Logic

**Trigger:** Key player injury/rest announcement within 2 hours of tipoff
where the sportsbook line moves ≥3 points but Polymarket price hasn't
fully adjusted.

**Entry conditions (all must be true):**
1. Player ruled out is top-3 in minutes played for their team
2. Sportsbook line moved ≥3 points post-announcement
3. Polymarket price delta vs implied sportsbook probability ≥5%
4. Game tips off in 30 minutes to 2 hours (enough time for execution)
5. Market has ≥$50K total volume (sufficient liquidity)

**Direction:** Trade toward the sportsbook-implied probability.
- If injured player's team was favored and line moved against them:
  buy the opponent
- If injured player's team was underdog and line moved further against:
  buy the opponent (momentum alignment)

**Entry size:** 3% of portfolio per trade ($300 on $10K portfolio).

```
function shouldEnter(game, injuryReport):
  player = injuryReport.player
  if player.minutesRank > 3: return NO_TRADE

  sportsbookMove = abs(pregameLine - currentLine)
  if sportsbookMove < 3: return NO_TRADE

  impliedProb = sportsbookToProb(currentLine)
  polymarketPrice = game.currentPrice
  mispricing = abs(impliedProb - polymarketPrice)
  if mispricing < 0.05: return NO_TRADE

  timeToTipoff = game.tipoff - now()
  if timeToTipoff < 30min or timeToTipoff > 2h: return NO_TRADE
  if game.totalVolume < 50000: return NO_TRADE

  if polymarketPrice < impliedProb:
    return BUY_YES at polymarketPrice
  else:
    return BUY_NO at (1 - polymarketPrice)
```

---

## Exit Logic

**Resolution exit:** Hold until game resolves (final score).
NBA game markets resolve at final whistle — no early exit needed
for winning trades.

**Pre-game stop loss:** If Polymarket price moves 8% against position
before tipoff (new information invalidates thesis), exit immediately.

**Hedge trigger:** If a second injury report affects the other team
before tipoff, re-evaluate edge. If mispricing shrinks below 2%, exit.

```
function shouldExit(position):
  if game.isResolved: return RESOLUTION
  if unrealizedLossPct >= 0.08 and not game.isLive: return STOP_LOSS
  if currentMispricing < 0.02: return EDGE_GONE

  return HOLD_TO_RESOLUTION
```

---

## Risk Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Max position size | $300 (3% of portfolio) | Single-game risk limit |
| Stop loss | 8% pre-game move against | Limits loss to ~$24 per trade |
| Max concurrent positions | 3 | Diversify across games |
| Max daily trades | 5 | Avoid overtrading on busy slates |
| Circuit breaker | 4 consecutive losses | Pause 24h, review edge thesis |
| Max drawdown | 15% of portfolio ($1,500) | Hard stop — halt all trading |
| Min time to tipoff | 30 minutes | Ensure execution time |

---

## Backtest Success Criteria

| Metric | Minimum | Target |
|--------|---------|--------|
| Win rate | >55% | 60% |
| Profit factor | >1.2 | 1.4 |
| Max drawdown | <15% | <10% |
| Trade count | ≥30 | 50+ |
| Avg profit per trade | >$8 | $15 |
| Edge decay | <2%/month | Stable across season |

**Backtest period:** 2024-2025 NBA season (Oct 2024 — Jun 2025).
**Data sources:** Polymarket API (price history), NBA API (injury reports,
box scores), odds-api.com (sportsbook lines).

---

## Data Requirements

| Data Point | Source | Update Frequency |
|------------|--------|------------------|
| Game schedule | NBA API | Daily |
| Injury reports | NBA official injury report | 2h and 30min pre-game |
| Sportsbook lines | The Odds API | Real-time |
| Polymarket prices | Polymarket CLOB API | Real-time |
| Player minutes/stats | NBA API / Basketball Reference | Daily |
| Historical game results | NBA API | Post-game |

---

## Implementation Notes

- Strategy archetype: `momentum-trader` (from strategy-patterns skill)
- Primary signal: sportsbook-to-Polymarket price divergence after injury news
- No ML required — rule-based with clear entry/exit thresholds
- Key dependency: The Odds API for real-time sportsbook lines
- Dashboard metrics: active positions, upcoming games with alerts,
  injury report feed, sportsbook vs Polymarket price comparison
