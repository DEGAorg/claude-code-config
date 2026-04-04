import { existsSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, type BrowserContext, type Browser } from "playwright";

const PROJECT_ROOT = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
);

const AUTH_DIR = resolve(PROJECT_ROOT, "auth");
const DEFAULT_ACCOUNT = "default";

/**
 * Resolve the storage-state.json path for a given account.
 * Creates the account directory if it doesn't exist.
 */
export function getStorageStatePath(account?: string): string {
  const name = account ?? DEFAULT_ACCOUNT;
  const accountDir = resolve(AUTH_DIR, name);
  if (!existsSync(accountDir)) {
    mkdirSync(accountDir, { recursive: true });
  }
  return resolve(accountDir, "storage-state.json");
}

/**
 * Check whether a saved browser session exists for the given account.
 */
export function hasStoredSession(account?: string): boolean {
  const path = getStorageStatePath(account);
  return existsSync(path);
}

/**
 * Validate that a stored session is still usable by loading it
 * and navigating to a lightweight DoraHacks page.
 *
 * Returns true if the session loads and the page indicates a
 * logged-in state, false otherwise.
 */
export async function validateSession(
  account?: string,
): Promise<boolean> {
  if (!hasStoredSession(account)) {
    return false;
  }

  const storagePath = getStorageStatePath(account);
  let browser: Browser | undefined;

  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({
      storageState: storagePath,
    });
    const page = await context.newPage();

    await page.goto("https://dorahacks.io/home", {
      waitUntil: "domcontentloaded",
      timeout: 15_000,
    });

    // A logged-in user has an avatar or profile element in the header.
    // If we find one within a short timeout, the session is valid.
    const loggedIn = await page
      .waitForSelector(
        "[class*='avatar'], [class*='Avatar'], [class*='user-info']",
        { timeout: 5_000 },
      )
      .then(() => true)
      .catch(() => false);

    await context.close();
    return loggedIn;
  } catch {
    return false;
  } finally {
    if (browser) await browser.close();
  }
}

/**
 * Launch a headed browser, navigate to DoraHacks, and wait for the
 * user to log in manually. Once the user confirms login is complete
 * (by pressing Enter in the terminal), the browser context is saved
 * to `auth/<account>/storage-state.json` for reuse in subsequent runs.
 */
export async function login(account?: string): Promise<void> {
  const storagePath = getStorageStatePath(account);
  const name = account ?? DEFAULT_ACCOUNT;

  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  await page.goto("https://dorahacks.io/login");

  console.log(
    `\n[auth] Browser opened at DoraHacks login page.`
    + `\n[auth] Account: ${name}`
    + `\n[auth] Please log in manually.`
    + `\n[auth] Once logged in, press Enter here to save the session.\n`,
  );

  await waitForEnter();

  await context.storageState({ path: storagePath });
  console.log(`[auth] Session saved to ${storagePath}`);

  await context.close();
  await browser.close();
}

/**
 * Create a browser context that reloads the saved session for the
 * given account. Returns both the browser instance and the context —
 * the caller is responsible for closing them when done.
 *
 * If no stored session exists, launches the interactive login flow.
 */
export async function loadSession(account?: string): Promise<{
  browser: Browser;
  context: BrowserContext;
}> {
  const name = account ?? DEFAULT_ACCOUNT;

  if (!hasStoredSession(account)) {
    console.log(
      `[auth] No saved session for account "${name}" `
      + `— launching login flow...`,
    );
    await login(account);
  }

  const storagePath = getStorageStatePath(account);
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext({
    storageState: storagePath,
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
