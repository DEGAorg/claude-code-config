# Plan: Canon wallet v1 — auto-generate per-project burner on canon-start

## Context

Canon automations trade real money on Polymarket but currently have no
user-facing wallet setup. Users must generate a private key manually
(via the test-only `canon/templates/__tests__/gen-burner.ts`), export
`POLYMARKET_PRIVATE_KEY`, and fund the address themselves. There is no
wizard, no auto-instantiation, and no abstraction that would let us
swap in macOS Keychain or a hardware wallet later.

This plan ships v1: a project-local wallet with zero-friction
generation during `/canon-start`, a `WalletStore` abstraction to
decouple storage from consumers, and a `canon-cli wallet` subcommand
surfacing `ensure`, `address`, and `info` operations. Different
projects (and therefore different strategies) get different wallets
automatically, because storage is scoped to `.canon/wallet.env` in the
project root — not a user-global file.

Out of scope for v1 (deferred to follow-up plans):

- Balance + per-automation spend-cap enforcement before a strategy runs
- Keychain / libsecret / DPAPI backends
- `wallet import`, `wallet rotate`, hardware wallets, Safe/AA
- User confirmations, key-reveal flows, QR codes

## Requirements

1. `WalletStore` interface + `FileWalletStore` implementation stored at
   `.canon/wallet.env` (mode 0600), project-local so each project gets
   its own wallet.
2. `canon-cli wallet ensure` generates a fresh burner if none exists;
   idempotent (prints address if one already exists, never overwrites).
3. `canon-cli wallet address` prints the wallet address (this is the
   `getWalletAddress` surface the agent will call).
4. `canon-cli wallet info` prints address + on-chain balance.
5. `auth.ts::requireAuth()` delegates to the store; existing
   `POLYMARKET_PRIVATE_KEY` env var remains a valid fallback for
   back-compat.
6. `/canon-start` init phase calls `canon-cli wallet ensure` before
   scaffolding, so every Canon project gets a wallet automatically and
   the user sees the "fund this address" message exactly once.
7. The test-only `gen-burner.ts` is removed; nothing in the repo
   should hand-roll wallet creation after this plan lands.

## Approach

### Storage layout

```
<project-root>/
  .canon/
    wallet.env        # POLYMARKET_PRIVATE_KEY=0x...  (mode 0600)
    state.json        # existing TUI state
    config.yaml       # existing
```

`.canon/` is already gitignored in generated projects. `wallet.env`
lives alongside existing Canon state, which means:

- Per-project wallets fall out naturally — different strategy repos,
  different wallets.
- No user-global collisions.
- When we add Keychain later, the `FileWalletStore` is swapped for a
  `KeychainWalletStore` behind the same interface; callers don't
  change.

### `WalletStore` interface

```ts
// canon/cli/wallet-store.ts
export interface WalletStore {
  hasWallet(): Promise<boolean>;
  getAddress(): Promise<string>;
  getPrivateKey(): Promise<string>;
  ensure(): Promise<{ address: string; created: boolean }>;
}
```

Single implementation in v1: `FileWalletStore` reads/writes
`.canon/wallet.env`, uses `ethers.Wallet.createRandom()` on `ensure()`,
writes with `{ mode: 0o600 }`, and refuses to overwrite.

### `auth.ts` migration

`requireAuth()` becomes:

1. If `POLYMARKET_PRIVATE_KEY` env is set → use it (back-compat, CI).
2. Else if `walletStore.hasWallet()` → load from store.
3. Else throw `AuthError` directing user to run `canon-cli wallet ensure`.

### `/canon-start` hook

`canon/commands/canon-start.md` step 3 ("Phase: init") currently runs
`canon-init`. Add a line after init completes that runs
`canon-cli wallet ensure` — idempotent, prints the address and the
"fund with USDC.e on Polygon" message on first run, prints the address
silently on subsequent runs. One line, no narration, consistent with
the strict output rules already in canon-start.

## Progress log

- [x] Write failing tests for `WalletStore` / `FileWalletStore` in `canon/cli/__tests__/wallet-store.test.ts` — cover: no wallet → `getAddress` rejects; `ensure()` creates wallet and persists; second `ensure()` is idempotent and reports `created: false`; file written with mode 0600; `POLYMARKET_PRIVATE_KEY` line present and parseable
- [x] Implement `canon/cli/wallet-store.ts` — `WalletStore` interface, `FileWalletStore` class using `ethers.Wallet.createRandom()`, writes `.canon/wallet.env` mode 0600, refuses overwrite (deps: 1)
- [x] Write failing tests for `wallet` subcommand in `canon/cli/commands/__tests__/wallet.test.ts` — `ensure` first-run prints address + funding prompt, second-run reports existing, `address` prints address, `info` prints address + balance shape (deps: 2)
- [x] Implement `canon/cli/commands/wallet.ts` with `ensure` / `address` / `info` subcommands, and register `wallet` in `canon/cli/canon-cli.ts` `COMMANDS` map (deps: 3)
- [x] Update `canon/cli/auth.ts` — `requireAuth()` falls back to `FileWalletStore.getPrivateKey()` when env is unset; update existing auth tests to cover the store path (deps: 2)
- [x] Hook `canon-cli wallet ensure` into `canon/commands/canon-start.md` step 3 init phase so every new Canon project auto-generates a wallet before scaffold (deps: 4)
- [x] Remove `canon/templates/__tests__/gen-burner.ts` and update any call sites / docs that referenced it (deps: 4)
- [x] Update `canon/skills/polymarket.md` and `canon/skills/canon-cli.md` to document `canon-cli wallet` subcommands and the auto-generation flow (deps: 4)

## Completion criteria

- [x] `pnpm --dir canon/cli exec vitest run __tests__/wallet-store.test.ts` exits 0
- [x] `pnpm --dir canon/cli exec vitest run commands/__tests__/wallet.test.ts` exits 0
- [x] `pnpm --dir canon/cli exec vitest run` (full suite) exits 0
- [x] `pnpm --dir canon/cli exec tsc --noEmit` exits 0
- [x] `rm -rf /tmp/canon-wallet-smoke && mkdir /tmp/canon-wallet-smoke && cd /tmp/canon-wallet-smoke && node <path>/canon-cli.ts wallet ensure && test -f .canon/wallet.env && test "$(stat -f '%Lp' .canon/wallet.env)" = "600"` exits 0
- [x] `node <path>/canon-cli.ts wallet address` prints a 0x-prefixed 42-char address
- [x] Running `wallet ensure` twice leaves the same address (idempotent) — verified by diff of two address outputs
- [x] `grep -c 'canon-cli wallet ensure' canon/commands/canon-start.md` returns ≥1
- [x] `test ! -f canon/templates/__tests__/gen-burner.ts` exits 0
- [x] `shellcheck` clean on any scripts touched
