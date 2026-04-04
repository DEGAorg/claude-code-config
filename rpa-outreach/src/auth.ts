import { existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, type BrowserContext, type Browser } from "playwright";

const PROJECT_ROOT = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
);

const AUTH_DIR = resolve(PROJECT_ROOT, "auth");
const STORAGE_STATE_PATH = resolve(AUTH_DIR, "storage-state.json");

/**
 * Check whether a saved browser session exists.
 */
export function hasStoredSession(): boolean {
  return existsSync(STORAGE_STATE_PATH);
}

/**
 * Launch a headed browser, navigate to DoraHacks, and wait for the
 * user to log in manually. Once the user confirms login is complete
 * (by pressing Enter in the terminal), the browser context is saved
 * to `auth/storage-state.json` for reuse in subsequent runs.
 */
export async function login(): Promise<void> {
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  await page.goto("https://dorahacks.io/login");

  console.log(
    "\n[auth] Browser opened at DoraHacks login page.\n" +
    "[auth] Please log in manually.\n" +
    "[auth] Once logged in, press Enter here to save the session.\n",
  );

  await waitForEnter();

  await context.storageState({ path: STORAGE_STATE_PATH });
  console.log(`[auth] Session saved to ${STORAGE_STATE_PATH}`);

  await context.close();
  await browser.close();
}

/**
 * Create a browser context that reloads the saved session.
 * Returns both the browser instance and the context — the caller
 * is responsible for closing them when done.
 *
 * Throws if no stored session exists. Call `login()` first.
 */
export async function loadSession(): Promise<{
  browser: Browser;
  context: BrowserContext;
}> {
  if (!hasStoredSession()) {
    console.log("[auth] No saved session found — launching login flow...");
    await login();
  }

  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext({
    storageState: STORAGE_STATE_PATH,
  });

  return { browser, context };
}

function waitForEnter(): Promise<void> {
  return new Promise((resolve) => {
    process.stdin.setRawMode?.(false);
    process.stdin.resume();
    process.stdin.once("data", () => {
      process.stdin.pause();
      resolve();
    });
  });
}
