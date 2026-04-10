# Demo Voiceover — Mar 30, 2026

## Intro

Canon is a prediction market platform powered by AI agents. Instead of
manually writing trading strategies, backtesting them, and wiring up
execution — you describe what you want, and the agents build it for you.

Today we're demonstrating the full Canon pipeline end-to-end. We start
with an empty folder. No code, no dependencies, no project structure. By
the end, we'll have a running NBA Championship futures scanner —
comparing sportsbook odds against Polymarket prices to detect mispricings
in real time.

The entire process is driven by the Conductor — an autonomous agent that
scaffolds the project, selects the strategy, implements the code, runs
the tests, and launches the automation. We make one decision: which
market to target. The agent handles everything else.

Let's start.

---

## Canon Init

We start with an empty directory. No code, no config, nothing. We run
`/canon-init` and Canon checks our environment — makes sure the tools
are installed, the engine is ready. It writes a single launcher script.
That's all we need.

## Launch

We run `canon.sh` and it opens the Conductor — our agent interface. On
the left, the AI agent. On the right, a live state panel that tracks
everything happening in the project.

## Canon Start

We type `/canon-start` and the agent takes over. It detects this is a
fresh project and begins the scaffold phase — fetching agent personas,
domain skills, strategy templates, and generating the entire project
structure. We can see each step in the state panel as it happens.

## Strategy Selection

The agent doesn't just build blindly. It asks us what we want — which
strategy, which market. We pick NBA Championship Futures, and it loads a
full template bundle with types, a runner, test harnesses, and a
pre-filled execution plan.

## Build Phase

Now the agent reads the plan and starts implementing. It writes the
strategy logic — config, signal detection, risk management — item by
item. Each completed item shows up in the state panel. When it hits an
issue — a type error, a failing test — it fixes it and moves on. No
manual intervention.

## Run Phase

Once all checks pass, the agent launches the strategy. The scanner goes
live — polling sportsbook odds, comparing them against Polymarket
prices, looking for mispricings in real time. Cycles, signals, errors —
all visible in the state panel.

## Wrap Up

From an empty directory to a running prediction market scanner. The
agent handled the scaffolding, the strategy selection, the
implementation, the debugging, and the execution. We made one choice —
which strategy to run. Everything else was autonomous.

This is Canon — AI-powered prediction market research, built on the
Conductor agent framework by DEGA.
