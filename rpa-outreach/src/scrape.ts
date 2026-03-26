import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { Browser, BrowserContext, Page } from "playwright";
import { loadSession } from "./auth.js";
import { getDb, upsertProspect } from "./db.js";
import type { ProspectInsert } from "./db.js";
import type { SelectorsConfig, ScraperSelectors } from "./types.js";

const PROJECT_ROOT = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
);

const SELECTORS_PATH = resolve(PROJECT_ROOT, "config", "selectors.json");
const DEFAULTS_PATH = resolve(PROJECT_ROOT, "config", "defaults.json");

/** Milliseconds to wait for SPA content after navigation. */
const SPA_SETTLE_MS = 5000;

interface ScrapeResult {
  total: number;
  inserted: number;
  updated: number;
  skipped: number;
}

/**
 * Load scraper selectors from config/selectors.json.
 * Throws if selectors are missing or empty.
 */
function loadSelectors(): ScraperSelectors {
  const raw = readFileSync(SELECTORS_PATH, "utf-8");
  const config = JSON.parse(raw) as SelectorsConfig;
  const s = config.scraper;

  if (!s.profile_list_container || !s.profile_card) {
    throw new Error(
      "Scraper selectors not configured. Run recon first: rpa-outreach recon",
    );
  }

  return s;
}

/**
 * Load scrape delay from config/defaults.json.
 */
function loadScrapeDelay(): number {
  try {
    const raw = readFileSync(DEFAULTS_PATH, "utf-8");
    const defaults = JSON.parse(raw) as { scrape_delay_ms?: number };
    return defaults.scrape_delay_ms ?? 2000;
  } catch {
    return 2000;
  }
}

/**
 * Extract profile data from a single card element using the configured
 * selectors. Runs inside the browser via page.evaluate.
 */
async function extractProfiles(
  page: Page,
  selectors: ScraperSelectors,
  hackathonUrl: string,
): Promise<ProspectInsert[]> {
  return page.evaluate(
    ({ sel, sourceUrl }) => {
      const container = document.querySelector(sel.profile_list_container);
      if (!container) return [];

      const cards = container.querySelectorAll(sel.profile_card);
      const profiles: Array<{
        username: string;
        profile_url: string;
        display_name: string;
        bio: string;
        tags: string;
        source_hackathon: string;
      }> = [];

      for (const card of cards) {
        let username = "";
        let profileUrl = "";
        let displayName = "";
        let bio = "";
        let tags = "";

        // Extract profile URL
        if (sel.profile_url) {
          const linkEl = card.querySelector(sel.profile_url);
          if (linkEl) {
            const href = linkEl.getAttribute("href") ?? "";
            profileUrl = href.startsWith("http")
              ? href
              : `https://dorahacks.io${href}`;
          }
        }

        // Extract username
        if (sel.username) {
          const usernameEl = card.querySelector(sel.username);
          if (usernameEl) {
            username = (usernameEl.textContent ?? "").trim();
          }
        }

        // If no dedicated username selector, derive from profile URL
        if (!username && profileUrl) {
          const segments = profileUrl.split("/").filter(Boolean);
          username = segments[segments.length - 1] ?? "";
        }

        // Display name defaults to username
        displayName = username;

        // Extract bio
        if (sel.bio) {
          const bioEl = card.querySelector(sel.bio);
          if (bioEl) {
            bio = (bioEl.textContent ?? "").trim();
          }
        }

        // Extract tags
        if (sel.tags) {
          const tagEls = card.querySelectorAll(sel.tags);
          const tagList: string[] = [];
          for (const tagEl of tagEls) {
            const text = (tagEl.textContent ?? "").trim();
            if (text) tagList.push(text);
          }
          tags = tagList.join(",");
        }

        // Only include profiles with a username
        if (username) {
          profiles.push({
            username,
            profile_url: profileUrl,
            display_name: displayName,
            bio,
            tags,
            source_hackathon: sourceUrl,
          });
        }
      }

      return profiles;
    },
    { sel: selectors, sourceUrl: hackathonUrl },
  );
}

/**
 * Scrape a single DoraHacks hackathon participant page.
 *
 * Navigates to the URL, waits for SPA rendering, extracts profiles
 * using selectors from config/selectors.json, and upserts each
 * profile into the SQLite database.
 */
export async function scrapeSinglePage(
  hackathonUrl: string,
  dbPath?: string,
): Promise<ScrapeResult> {
  const selectors = loadSelectors();
  const scrapeDelay = loadScrapeDelay();

  let browser: Browser | undefined;
  let context: BrowserContext | undefined;

  try {
    const session = await loadSession();
    browser = session.browser;
    context = session.context;

    const page = await context.newPage();
    const label = "[scrape]";

    console.log(`${label} Navigating to ${hackathonUrl}`);

    try {
      await page.goto(hackathonUrl, {
        waitUntil: "networkidle",
        timeout: 30_000,
      });
    } catch {
      console.log(`${label} networkidle timeout — waiting for SPA settle`);
      await page.waitForTimeout(SPA_SETTLE_MS);
    }

    // Extra settle for SPA rendering
    await page.waitForTimeout(SPA_SETTLE_MS);

    // Wait for profile cards to appear
    try {
      await page.waitForSelector(selectors.profile_card, { timeout: 10_000 });
    } catch {
      console.log(
        `${label} Profile cards not found with selector: ${selectors.profile_card}`,
      );
    }

    // Brief delay for any remaining async rendering
    await page.waitForTimeout(scrapeDelay);

    console.log(`${label} Extracting profiles...`);
    const profiles = await extractProfiles(page, selectors, hackathonUrl);
    console.log(`${label} Found ${profiles.length} profiles on page`);

    await page.close();

    // Store in DB
    const db = getDb(dbPath);
    let inserted = 0;
    let updated = 0;
    let skipped = 0;

    for (const profile of profiles) {
      if (!profile.username) {
        skipped++;
        continue;
      }

      const rowId = upsertProspect(db, profile);
      if (rowId > 0) {
        // upsert always returns a rowid; check if it was a new row
        // by comparing with the profile count before
        inserted++;
      } else {
        updated++;
      }
    }

    // Since upsert doesn't distinguish insert vs update by rowid alone,
    // report total processed minus skipped
    const result: ScrapeResult = {
      total: profiles.length,
      inserted: profiles.length - skipped,
      updated: 0,
      skipped,
    };

    console.log(
      `${label} Done — ${result.total} profiles found, ` +
      `${result.inserted} stored, ${result.skipped} skipped`,
    );

    return result;
  } finally {
    if (context) await context.close();
    if (browser) await browser.close();
  }
}
