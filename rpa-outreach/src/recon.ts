import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { Page, BrowserContext, Browser } from "playwright";
import { loadSession } from "./auth.js";
import type { ScraperSelectors } from "./types.js";

const PROJECT_ROOT = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
);

const RECON_DIR = resolve(PROJECT_ROOT, "recon");
const SELECTORS_PATH = resolve(PROJECT_ROOT, "config", "selectors.json");

/** Milliseconds to wait for SPA content to render after navigation. */
const SPA_SETTLE_MS = 5000;

/** URLs known to contain hackathon participant/BUIDLer listings. */
const RECON_URLS = [
  "https://dorahacks.io/hackathon/solana-renaissance/buidl",
  "https://dorahacks.io/hackathon/move-on-aptos-iv/buidl",
  "https://dorahacks.io/hackathon/sui-overflow/buidl",
];

interface ReconResult {
  url: string;
  htmlPath: string;
  screenshotPath: string;
}

/**
 * Navigate to DoraHacks hackathon BUIDLer pages, save full-page HTML
 * and screenshots to `recon/`, then analyze the DOM to discover CSS
 * selectors for scraper fields.
 *
 * Returns the discovered scraper selectors object.
 */
export async function reconScraperPages(
  urls?: string[],
): Promise<ScraperSelectors> {
  mkdirSync(RECON_DIR, { recursive: true });

  const targetUrls = urls ?? RECON_URLS;
  let browser: Browser | undefined;
  let context: BrowserContext | undefined;

  try {
    const session = await loadSession();
    browser = session.browser;
    context = session.context;

    const results: ReconResult[] = [];
    let discoveredSelectors: ScraperSelectors | undefined;

    for (const [index, url] of targetUrls.entries()) {
      const slug = slugFromUrl(url);
      const label = `[recon ${index + 1}/${targetUrls.length}]`;

      console.log(`${label} Navigating to ${url}`);
      const page = await context.newPage();

      try {
        await page.goto(url, { waitUntil: "networkidle", timeout: 30_000 });
      } catch {
        console.log(`${label} networkidle timeout — waiting for SPA settle`);
        await page.waitForTimeout(SPA_SETTLE_MS);
      }

      // Extra settle time for SPA rendering
      await page.waitForTimeout(SPA_SETTLE_MS);

      // Save full-page HTML snapshot
      const htmlContent = await page.content();
      const htmlPath = resolve(RECON_DIR, `${slug}.html`);
      writeFileSync(htmlPath, htmlContent, "utf-8");
      console.log(`${label} Saved HTML → ${htmlPath}`);

      // Save full-page screenshot
      const screenshotPath = resolve(RECON_DIR, `${slug}.png`);
      await page.screenshot({ path: screenshotPath, fullPage: true });
      console.log(`${label} Saved screenshot → ${screenshotPath}`);

      results.push({ url, htmlPath, screenshotPath });

      // Analyze DOM on the first page that has content
      if (!discoveredSelectors) {
        console.log(`${label} Analyzing DOM for selectors...`);
        discoveredSelectors = await analyzePage(page);
        if (discoveredSelectors.profile_card) {
          console.log(`${label} Selectors discovered successfully`);
        } else {
          console.log(`${label} No profile cards found — will try next page`);
          discoveredSelectors = undefined;
        }
      }

      await page.close();
    }

    if (!discoveredSelectors) {
      console.log(
        "[recon] WARNING: Could not auto-discover selectors from any page. " +
        "HTML snapshots saved — inspect manually and update config/selectors.json.",
      );
      return emptySelectors();
    }

    writeSelectorsConfig(discoveredSelectors);
    return discoveredSelectors;
  } finally {
    if (context) await context.close();
    if (browser) await browser.close();
  }
}

/**
 * Analyze a loaded DoraHacks BUIDLer page to discover CSS selectors
 * for profile list elements. Runs heuristic detection inside the page
 * context via `page.evaluate`.
 */
async function analyzePage(page: Page): Promise<ScraperSelectors> {
  return page.evaluate(() => {
    const selectors: Record<string, string> = {
      profile_list_container: "",
      profile_card: "",
      username: "",
      profile_url: "",
      bio: "",
      tags: "",
    };

    // Strategy: find the largest repeating card-like structure.
    // DoraHacks BUIDLer pages render project/profile cards in a grid or list.
    // We look for containers with multiple similar children that contain links.

    // Candidate container selectors — ordered by specificity
    const containerCandidates = [
      // Data-attribute patterns common in React SPAs
      '[data-testid*="buidl"]',
      '[data-testid*="project"]',
      '[data-testid*="card"]',
      // Class-based patterns from DoraHacks
      ".buidl-list",
      ".project-list",
      ".buidl-card-list",
      ".hack-card-list",
      ".card-list",
      ".participant-list",
    ];

    // Try known container selectors first
    for (const sel of containerCandidates) {
      const el = document.querySelector(sel);
      if (el && el.children.length >= 3) {
        selectors["profile_list_container"] = sel;
        break;
      }
    }

    // Fallback: find any element whose direct children are many similar
    // elements (likely a list of cards)
    if (!selectors["profile_list_container"]) {
      const allDivs = document.querySelectorAll(
        "main div, [id='root'] div, [id='app'] div",
      );
      let bestContainer: Element | null = null;
      let bestCount = 0;

      for (const div of allDivs) {
        if (div.children.length < 5) continue;

        // Check if children share a common tag + class pattern
        const firstChild = div.children[0];
        if (!firstChild) continue;
        const childTag = firstChild.tagName;
        const childClasses = Array.from(firstChild.classList);

        if (childClasses.length === 0) continue;

        let matchCount = 0;
        for (const child of div.children) {
          if (
            child.tagName === childTag &&
            childClasses.every((c) => child.classList.contains(c))
          ) {
            matchCount++;
          }
        }

        // Must have many similar children and contain links (profile URLs)
        const hasLinks = div.querySelectorAll("a[href]").length >= matchCount;
        if (matchCount > bestCount && matchCount >= 5 && hasLinks) {
          bestCount = matchCount;
          bestContainer = div;
        }
      }

      if (bestContainer) {
        // Build a selector for this container
        const containerId = bestContainer.id;
        const containerClasses = Array.from(bestContainer.classList);

        if (containerId) {
          selectors["profile_list_container"] = `#${containerId}`;
        } else if (containerClasses.length > 0) {
          selectors["profile_list_container"] =
            `.${containerClasses.join(".")}`;
        }
      }
    }

    // Discover card selector from container's children
    const container = selectors["profile_list_container"]
      ? document.querySelector(selectors["profile_list_container"])
      : null;

    if (container && container.children.length > 0) {
      const firstCard = container.children[0] as HTMLElement;
      const cardClasses = Array.from(firstCard.classList);

      if (cardClasses.length > 0) {
        selectors["profile_card"] = `.${cardClasses.join(".")}`;
      } else {
        selectors["profile_card"] = firstCard.tagName.toLowerCase();
      }

      // Within a card, find the profile link (username + URL)
      const links = firstCard.querySelectorAll("a[href]");
      for (const link of links) {
        const href = link.getAttribute("href") ?? "";
        // DoraHacks profile links typically contain /user/ or /buidl/
        if (
          href.includes("/user/") ||
          href.includes("/buidl/") ||
          href.includes("/buidler/")
        ) {
          const linkClasses = Array.from(link.classList);
          selectors["profile_url"] = linkClasses.length > 0
            ? `a.${linkClasses.join(".")}`
            : `a[href*="${href.split("/").slice(0, -1).pop() ?? "user"}"]`;

          // The link text is often the username/display name
          const nameEl = link.querySelector("h2, h3, h4, span, p");
          if (nameEl) {
            const nameClasses = Array.from(nameEl.classList);
            selectors["username"] = nameClasses.length > 0
              ? `${nameEl.tagName.toLowerCase()}.${nameClasses.join(".")}`
              : `${selectors["profile_url"]} ${nameEl.tagName.toLowerCase()}`;
          } else {
            selectors["username"] = selectors["profile_url"];
          }
          break;
        }
      }

      // Find bio/description text — look for paragraph or span with substantial text
      const textEls = firstCard.querySelectorAll("p, span, div");
      for (const el of textEls) {
        const text = el.textContent?.trim() ?? "";
        if (text.length > 30 && text.length < 500) {
          const elClasses = Array.from(el.classList);
          if (elClasses.length > 0) {
            selectors["bio"] = `.${elClasses.join(".")}`;
          } else {
            selectors["bio"] =
              `${selectors["profile_card"]} ${el.tagName.toLowerCase()}`;
          }
          break;
        }
      }

      // Find tags — look for badge/tag-like elements (small text in containers)
      const tagCandidates = firstCard.querySelectorAll(
        "span, a, div, label",
      );
      for (const el of tagCandidates) {
        const text = el.textContent?.trim() ?? "";
        const elClasses = Array.from(el.classList).join(" ");
        const isTagLike =
          (text.length > 0 && text.length < 30) &&
          (elClasses.includes("tag") ||
            elClasses.includes("badge") ||
            elClasses.includes("label") ||
            elClasses.includes("chip") ||
            elClasses.includes("category"));
        if (isTagLike) {
          selectors["tags"] = `.${Array.from(el.classList).join(".")}`;
          break;
        }
      }
    }

    return selectors as unknown as {
      profile_list_container: string;
      profile_card: string;
      username: string;
      profile_url: string;
      bio: string;
      tags: string;
    };
  });
}

/**
 * Write discovered scraper selectors to `config/selectors.json`,
 * preserving any existing DM selectors.
 */
function writeSelectorsConfig(scraperSelectors: ScraperSelectors): void {
  let existing: Record<string, unknown> = {};
  try {
    const raw = readFileSync(SELECTORS_PATH, "utf-8");
    existing = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    // File missing or invalid — start fresh
  }

  const config = {
    scraper: scraperSelectors,
    dm: existing["dm"] ?? {
      dm_button: "",
      message_input: "",
      send_button: "",
      confirmation_indicator: "",
    },
  };

  writeFileSync(SELECTORS_PATH, JSON.stringify(config, null, 2) + "\n", "utf-8");
  console.log(`[recon] Scraper selectors written to ${SELECTORS_PATH}`);
}

function slugFromUrl(url: string): string {
  const parts = new URL(url).pathname.split("/").filter(Boolean);
  return parts.join("-") || "unknown";
}

function emptySelectors(): ScraperSelectors {
  return {
    profile_list_container: "",
    profile_card: "",
    username: "",
    profile_url: "",
    bio: "",
    tags: "",
  };
}
