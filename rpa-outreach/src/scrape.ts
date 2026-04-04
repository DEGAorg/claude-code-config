import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { Browser, BrowserContext, Page } from "playwright";
import { loadSession } from "./auth.js";
import { getPool, upsertProspect, isDuplicate } from "./db.js";
import type { ProspectInsert } from "./db.js";
import type {
  SelectorsConfig,
  ScraperSelectors,
  HackathonEntry,
  DefaultsConfig,
} from "./types.js";

const PROJECT_ROOT = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
);

const SELECTORS_PATH = resolve(
  PROJECT_ROOT, "config", "selectors.json",
);
const DEFAULTS_PATH = resolve(
  PROJECT_ROOT, "config", "defaults.json",
);
const HACKATHONS_PATH = resolve(
  PROJECT_ROOT, "config", "hackathons.json",
);

const SPA_SETTLE_MS = 5000;
const SCROLL_PAUSE_MS = 2000;
const MAX_SCROLL_ATTEMPTS = 50;
const DEFAULT_PAGE_DELAY_MS = 3000;

interface ScrapeResult {
  total: number;
  inserted: number;
  updated: number;
  skipped: number;
}

interface MultiScrapeResult {
  hackathons: number;
  totalProfiles: number;
  totalInserted: number;
  totalSkipped: number;
  perHackathon: Array<{
    url: string;
    name: string;
    result: ScrapeResult;
  }>;
}

function loadSelectors(): ScraperSelectors {
  const raw = readFileSync(SELECTORS_PATH, "utf-8");
  const config = JSON.parse(raw) as SelectorsConfig;
  const s = config.scraper;

  if (!s.profile_list_container || !s.profile_card) {
    throw new Error(
      "Scraper selectors not configured. Run recon first: "
      + "rpa-outreach recon",
    );
  }

  return s;
}

function loadDefaults(): DefaultsConfig {
  const raw = readFileSync(DEFAULTS_PATH, "utf-8");
  return JSON.parse(raw) as DefaultsConfig;
}

function loadHackathons(): HackathonEntry[] {
  const raw = readFileSync(HACKATHONS_PATH, "utf-8");
  const entries = JSON.parse(raw) as HackathonEntry[];

  if (!Array.isArray(entries) || entries.length === 0) {
    throw new Error(
      "No hackathons configured in config/hackathons.json",
    );
  }

  return entries;
}

function randomDelay(minMs: number, maxMs: number): number {
  return Math.floor(
    Math.random() * (maxMs - minMs + 1),
  ) + minMs;
}

async function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

/**
 * Extract profile data from the page using configured selectors.
 * Runs inside the browser via page.evaluate.
 */
async function extractProfiles(
  page: Page,
  selectors: ScraperSelectors,
  hackathonUrl: string,
): Promise<ProspectInsert[]> {
  return page.evaluate(
    ({ sel, sourceUrl }) => {
      const container = document.querySelector(
        sel.profile_list_container,
      );
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
        let bio = "";
        let tags = "";

        if (sel.profile_url) {
          const linkEl = card.querySelector(sel.profile_url);
          if (linkEl) {
            const href = linkEl.getAttribute("href") ?? "";
            profileUrl = href.startsWith("http")
              ? href
              : `https://dorahacks.io${href}`;
          }
        }

        if (sel.username) {
          const usernameEl = card.querySelector(sel.username);
          if (usernameEl) {
            username = (usernameEl.textContent ?? "").trim();
          }
        }

        if (!username && profileUrl) {
          const segments = profileUrl.split("/").filter(Boolean);
          username = segments[segments.length - 1] ?? "";
        }

        if (sel.bio) {
          const bioEl = card.querySelector(sel.bio);
          if (bioEl) {
            bio = (bioEl.textContent ?? "").trim();
          }
        }

        if (sel.tags) {
          const tagEls = card.querySelectorAll(sel.tags);
          const tagList: string[] = [];
          for (const tagEl of tagEls) {
            const text = (tagEl.textContent ?? "").trim();
            if (text) tagList.push(text);
          }
          tags = tagList.join(",");
        }

        if (username) {
          profiles.push({
            username,
            profile_url: profileUrl,
            display_name: username,
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
 * Click the "Load More" button repeatedly to load all profiles.
 * Falls back to scrolling if no load-more button is configured.
 *
 * Stops when the button disappears or MAX_SCROLL_ATTEMPTS is reached.
 */
async function loadAllProfiles(
  page: Page,
  selectors: ScraperSelectors,
  label: string,
): Promise<void> {
  const loadMoreSelector = selectors.load_more_button;

  if (!loadMoreSelector) {
    console.log(`${label} No load_more_button selector — using scroll`);
    await loadAllProfiles(page, selectors, label);
    return;
  }

  for (let i = 0; i < MAX_SCROLL_ATTEMPTS; i++) {
    const cardCount = await page.evaluate(
      (sel) => {
        const container = document.querySelector(
          sel.profile_list_container,
        );
        if (!container) return 0;
        return container.querySelectorAll(sel.profile_card).length;
      },
      selectors,
    );

    const button = await page.$(loadMoreSelector);
    if (!button) {
      console.log(
        `${label} No more "Load More" button — `
        + `${cardCount} profiles loaded`,
      );
      break;
    }

    const isVisible = await button.isVisible();
    if (!isVisible) {
      console.log(
        `${label} "Load More" button hidden — `
        + `${cardCount} profiles loaded`,
      );
      break;
    }

    console.log(
      `${label} Click ${i + 1}: ${cardCount} profiles, `
      + `clicking Load More...`,
    );

    await button.scrollIntoViewIfNeeded();
    await button.click();
    await page.waitForTimeout(SCROLL_PAUSE_MS);
  }
}

/**
 * Scrape a single DoraHacks hackathon participant page.
 *
 * Handles infinite scroll to load all profiles, extracts them
 * using selectors from config/selectors.json, deduplicates by
 * username, and upserts into the Neon database.
 */
export async function scrapeSinglePage(
  hackathonUrl: string,
  account?: string,
): Promise<ScrapeResult> {
  const selectors = loadSelectors();
  const defaults = loadDefaults();

  let browser: Browser | undefined;
  let context: BrowserContext | undefined;

  try {
    const session = await loadSession(account);
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
      console.log(
        `${label} networkidle timeout — waiting for SPA settle`,
      );
      await page.waitForTimeout(SPA_SETTLE_MS);
    }

    await page.waitForTimeout(SPA_SETTLE_MS);

    try {
      await page.waitForSelector(
        selectors.profile_card, { timeout: 10_000 },
      );
    } catch {
      console.log(
        `${label} Profile cards not found: `
        + `${selectors.profile_card}`,
      );
    }

    await page.waitForTimeout(defaults.scrape_delay_ms);

    await loadAllProfiles(page, selectors, label);

    console.log(`${label} Extracting profiles...`);
    const profiles = await extractProfiles(
      page, selectors, hackathonUrl,
    );
    console.log(
      `${label} Found ${profiles.length} profiles on page`,
    );

    await page.close();

    const pool = await getPool();
    let inserted = 0;
    let skipped = 0;
    const seenUsernames = new Set<string>();

    for (const profile of profiles) {
      if (!profile.username) {
        skipped++;
        continue;
      }

      if (seenUsernames.has(profile.username)) {
        skipped++;
        continue;
      }
      seenUsernames.add(profile.username);

      if (await isDuplicate(pool, profile.username)) {
        skipped++;
        continue;
      }

      await upsertProspect(pool, profile);
      inserted++;
    }

    const result: ScrapeResult = {
      total: profiles.length,
      inserted,
      updated: 0,
      skipped,
    };

    console.log(
      `${label} Done — ${result.total} found, `
      + `${result.inserted} inserted, ${result.skipped} skipped`,
    );

    return result;
  } finally {
    if (context) await context.close();
    if (browser) await browser.close();
  }
}

/**
 * Scrape all hackathons from config/hackathons.json.
 *
 * Iterates each configured hackathon URL, handles pagination
 * via infinite scroll, deduplicates by username across all
 * hackathons, and applies rate-limited delays between pages.
 */
export async function scrapeAll(
  account?: string,
): Promise<MultiScrapeResult> {
  const hackathons = loadHackathons();
  const selectors = loadSelectors();
  const defaults = loadDefaults();
  const label = "[scrape]";

  const pageDelayMin = defaults.scrape_delay_ms;
  const pageDelayMax = Math.max(
    pageDelayMin * 2,
    DEFAULT_PAGE_DELAY_MS,
  );

  console.log(
    `${label} Starting multi-hackathon scrape `
    + `(${hackathons.length} hackathons)`,
  );

  let browser: Browser | undefined;
  let context: BrowserContext | undefined;

  const perHackathon: MultiScrapeResult["perHackathon"] = [];
  let totalProfiles = 0;
  let totalInserted = 0;
  let totalSkipped = 0;

  try {
    const session = await loadSession(account);
    browser = session.browser;
    context = session.context;

    const pool = await getPool();

    for (let i = 0; i < hackathons.length; i++) {
      const hackathon = hackathons[i];
      if (!hackathon) continue;

      console.log(
        `\n${label} [${i + 1}/${hackathons.length}] `
        + `${hackathon.name}: ${hackathon.url}`,
      );

      const page = await context.newPage();

      try {
        await page.goto(hackathon.url, {
          waitUntil: "networkidle",
          timeout: 30_000,
        });
      } catch {
        console.log(
          `${label} networkidle timeout — waiting for SPA`,
        );
        await page.waitForTimeout(SPA_SETTLE_MS);
      }

      await page.waitForTimeout(SPA_SETTLE_MS);

      try {
        await page.waitForSelector(
          selectors.profile_card, { timeout: 10_000 },
        );
      } catch {
        console.log(
          `${label} No profile cards found — skipping`,
        );
        await page.close();
        perHackathon.push({
          url: hackathon.url,
          name: hackathon.name,
          result: {
            total: 0, inserted: 0, updated: 0, skipped: 0,
          },
        });
        continue;
      }

      await page.waitForTimeout(defaults.scrape_delay_ms);

      await loadAllProfiles(page, selectors, label);

      console.log(`${label} Extracting profiles...`);
      const profiles = await extractProfiles(
        page, selectors, hackathon.url,
      );
      console.log(
        `${label} Found ${profiles.length} profiles`,
      );

      await page.close();

      let inserted = 0;
      let skipped = 0;
      const seenUsernames = new Set<string>();

      for (const profile of profiles) {
        if (!profile.username) {
          skipped++;
          continue;
        }

        if (seenUsernames.has(profile.username)) {
          skipped++;
          continue;
        }
        seenUsernames.add(profile.username);

        if (await isDuplicate(pool, profile.username)) {
          skipped++;
          continue;
        }

        await upsertProspect(pool, profile);
        inserted++;
      }

      const result: ScrapeResult = {
        total: profiles.length,
        inserted,
        updated: 0,
        skipped,
      };

      perHackathon.push({
        url: hackathon.url,
        name: hackathon.name,
        result,
      });

      totalProfiles += result.total;
      totalInserted += result.inserted;
      totalSkipped += result.skipped;

      console.log(
        `${label} ${hackathon.name}: ${result.inserted} inserted, `
        + `${result.skipped} skipped`,
      );

      if (i < hackathons.length - 1) {
        const delay = randomDelay(pageDelayMin, pageDelayMax);
        console.log(
          `${label} Rate limit pause: ${delay}ms`,
        );
        await sleep(delay);
      }
    }
  } finally {
    if (context) await context.close();
    if (browser) await browser.close();
  }

  console.log(
    `\n${label} Multi-scrape complete — `
    + `${hackathons.length} hackathons, `
    + `${totalProfiles} profiles found, `
    + `${totalInserted} inserted, `
    + `${totalSkipped} skipped`,
  );

  return {
    hackathons: hackathons.length,
    totalProfiles,
    totalInserted,
    totalSkipped,
    perHackathon,
  };
}
