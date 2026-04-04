import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { Page, BrowserContext, Browser } from "playwright";
import { loadSession } from "./auth.js";
import { loadHackathons } from "./config.js";
import type { DmSelectors, ScraperSelectors } from "./types.js";

const PROJECT_ROOT = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
);

const RECON_DIR = resolve(PROJECT_ROOT, "recon");
const SELECTORS_PATH = resolve(PROJECT_ROOT, "config", "selectors.json");

/** Milliseconds to wait for SPA content to render after navigation. */
const SPA_SETTLE_MS = 5000;

/** Load hackathon URLs from config/hackathons.json. */
function getReconUrls(): string[] {
  const hackathons = loadHackathons();
  return hackathons.map((h) => h.url);
}

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
  _account?: string,
): Promise<ScraperSelectors> {
  mkdirSync(RECON_DIR, { recursive: true });

  const targetUrls = urls ?? getReconUrls();
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

/** No default DM recon URLs — must be provided via CLI or from scraped data. */

/**
 * Navigate to DoraHacks profile page(s) and the DM/message page.
 * Saves HTML + screenshots, discovers CSS selectors for DM elements,
 * and writes them to `config/selectors.json`.
 *
 * Requires an authenticated session (the DM page is behind login).
 */
export async function reconDmPages(
  profileUrls?: string[],
  _account?: string,
): Promise<DmSelectors> {
  mkdirSync(RECON_DIR, { recursive: true });

  if (!profileUrls || profileUrls.length === 0) {
    console.log(
      "[recon-dm] No profile URLs provided. Run 'scrape' first, then pass " +
      "profile URLs with: rpa-outreach recon --dm-only --profile-url <url>",
    );
    return emptyDmSelectors();
  }
  const targetUrls = profileUrls;
  let browser: Browser | undefined;
  let context: BrowserContext | undefined;

  try {
    const session = await loadSession();
    browser = session.browser;
    context = session.context;

    let discoveredSelectors: DmSelectors | undefined;

    for (const [index, url] of targetUrls.entries()) {
      const slug = `dm-${slugFromUrl(url)}`;
      const label = `[recon-dm ${index + 1}/${targetUrls.length}]`;

      // --- Step 1: Navigate to the profile page ---
      console.log(`${label} Navigating to profile ${url}`);
      const page = await context.newPage();

      try {
        await page.goto(url, {
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

      // Save profile page HTML + screenshot
      const profileHtml = await page.content();
      const profileHtmlPath = resolve(RECON_DIR, `${slug}-profile.html`);
      writeFileSync(profileHtmlPath, profileHtml, "utf-8");
      console.log(`${label} Saved profile HTML → ${profileHtmlPath}`);

      const profileScreenshotPath = resolve(
        RECON_DIR,
        `${slug}-profile.png`,
      );
      await page.screenshot({
        path: profileScreenshotPath,
        fullPage: true,
      });
      console.log(
        `${label} Saved profile screenshot → ${profileScreenshotPath}`,
      );

      // --- Step 2: Find the DM button on the profile page ---
      const dmButtonSelector = await findDmButton(page);
      if (!dmButtonSelector) {
        console.log(
          `${label} No DM button found on profile — trying next`,
        );
        await page.close();
        continue;
      }
      console.log(
        `${label} Found DM button: ${dmButtonSelector}`,
      );

      // --- Step 3: Click DM button to open message page ---
      try {
        await page.click(dmButtonSelector, { timeout: 5000 });
      } catch {
        console.log(
          `${label} Could not click DM button — trying next profile`,
        );
        await page.close();
        continue;
      }

      // Wait for DM page / modal to load
      await page.waitForTimeout(SPA_SETTLE_MS);

      // Save DM page HTML + screenshot
      const dmHtml = await page.content();
      const dmHtmlPath = resolve(RECON_DIR, `${slug}-dm.html`);
      writeFileSync(dmHtmlPath, dmHtml, "utf-8");
      console.log(`${label} Saved DM page HTML → ${dmHtmlPath}`);

      const dmScreenshotPath = resolve(RECON_DIR, `${slug}-dm.png`);
      await page.screenshot({
        path: dmScreenshotPath,
        fullPage: true,
      });
      console.log(
        `${label} Saved DM screenshot → ${dmScreenshotPath}`,
      );

      // --- Step 4: Analyze the DM page for selectors ---
      console.log(`${label} Analyzing DM page for selectors...`);
      discoveredSelectors = await analyzeDmPage(page, dmButtonSelector);

      await page.close();

      if (discoveredSelectors.message_input) {
        console.log(`${label} DM selectors discovered successfully`);
        break;
      }

      console.log(
        `${label} Incomplete DM selectors — trying next profile`,
      );
      discoveredSelectors = undefined;
    }

    if (!discoveredSelectors) {
      console.log(
        "[recon-dm] WARNING: Could not auto-discover DM selectors. " +
          "HTML snapshots saved — inspect manually and update " +
          "config/selectors.json.",
      );
      return emptyDmSelectors();
    }

    writeDmSelectorsConfig(discoveredSelectors);
    return discoveredSelectors;
  } finally {
    if (context) await context.close();
    if (browser) await browser.close();
  }
}

/**
 * Find the DM/message button on a DoraHacks profile page.
 * Returns the CSS selector string or null if not found.
 */
async function findDmButton(page: Page): Promise<string | null> {
  return page.evaluate(() => {
    // Strategy 1: Look for buttons/links with messaging-related text
    const messagingKeywords = [
      "message",
      "dm",
      "direct message",
      "send message",
      "chat",
      "contact",
    ];

    const clickables = document.querySelectorAll(
      "a, button, [role='button']",
    );
    for (const el of clickables) {
      const text = (el.textContent ?? "").trim().toLowerCase();
      const ariaLabel = (
        el.getAttribute("aria-label") ?? ""
      ).toLowerCase();
      const title = (el.getAttribute("title") ?? "").toLowerCase();

      const combined = `${text} ${ariaLabel} ${title}`;
      const isMatch = messagingKeywords.some((kw) =>
        combined.includes(kw),
      );

      if (!isMatch) continue;

      // Build a selector for this element
      const id = el.id;
      if (id) return `#${id}`;

      const classes = Array.from(el.classList);
      if (classes.length > 0) {
        return `${el.tagName.toLowerCase()}.${classes.join(".")}`;
      }

      // Fallback: use data attributes
      const dataAttrs = Array.from(el.attributes).filter((a) =>
        a.name.startsWith("data-"),
      );
      for (const attr of dataAttrs) {
        return `[${attr.name}="${attr.value}"]`;
      }
    }

    // Strategy 2: Look for elements with messaging-related class names
    const classPatterns = [
      "[class*='message']",
      "[class*='dm']",
      "[class*='chat']",
      "[class*='contact']",
      "[class*='inbox']",
    ];

    for (const pattern of classPatterns) {
      const els = document.querySelectorAll(pattern);
      for (const el of els) {
        const tag = el.tagName.toLowerCase();
        if (
          tag === "a" ||
          tag === "button" ||
          el.getAttribute("role") === "button"
        ) {
          const classes = Array.from(el.classList);
          if (classes.length > 0) {
            return `${tag}.${classes.join(".")}`;
          }
        }
      }
    }

    // Strategy 3: Look for mail/envelope icons near clickable elements
    const iconPatterns = [
      "svg[class*='mail']",
      "svg[class*='message']",
      "i[class*='mail']",
      "i[class*='message']",
      "i[class*='envelope']",
      "img[alt*='message']",
      "[data-icon*='message']",
      "[data-icon*='mail']",
    ];

    for (const pattern of iconPatterns) {
      const icon = document.querySelector(pattern);
      if (!icon) continue;

      // Walk up to find the clickable parent
      let parent: Element | null = icon.parentElement;
      for (let i = 0; i < 4 && parent; i++) {
        const tag = parent.tagName.toLowerCase();
        if (
          tag === "a" ||
          tag === "button" ||
          parent.getAttribute("role") === "button"
        ) {
          const classes = Array.from(parent.classList);
          if (classes.length > 0) {
            return `${tag}.${classes.join(".")}`;
          }
          if (parent.id) return `#${parent.id}`;
        }
        parent = parent.parentElement;
      }
    }

    return null;
  });
}

/**
 * Analyze the DM/message page (or modal) to discover selectors
 * for the message input, send button, and confirmation indicator.
 */
async function analyzeDmPage(
  page: Page,
  dmButtonSelector: string,
): Promise<DmSelectors> {
  const pageSelectors = await page.evaluate(() => {
    const selectors: Record<string, string> = {
      message_input: "",
      send_button: "",
      confirmation_indicator: "",
    };

    // --- Message input field ---
    // Look for textarea first (most likely for message composition)
    const textareaPatterns = [
      "textarea[placeholder*='message' i]",
      "textarea[placeholder*='type' i]",
      "textarea[placeholder*='write' i]",
      "textarea[name*='message' i]",
      "textarea[class*='message' i]",
      "textarea[class*='input' i]",
      "textarea",
    ];

    for (const pattern of textareaPatterns) {
      const el = document.querySelector(pattern);
      if (el) {
        const id = el.id;
        if (id) {
          selectors["message_input"] = `#${id}`;
          break;
        }
        const classes = Array.from(el.classList);
        if (classes.length > 0) {
          selectors["message_input"] =
            `textarea.${classes.join(".")}`;
          break;
        }
        selectors["message_input"] = pattern;
        break;
      }
    }

    // Fallback: contenteditable div (used in rich-text editors)
    if (!selectors["message_input"]) {
      const editablePatterns = [
        "[contenteditable='true'][class*='message' i]",
        "[contenteditable='true'][class*='editor' i]",
        "[contenteditable='true'][class*='input' i]",
        "[contenteditable='true'][role='textbox']",
        "[contenteditable='true']",
      ];

      for (const pattern of editablePatterns) {
        const el = document.querySelector(pattern);
        if (el) {
          const classes = Array.from(el.classList);
          if (classes.length > 0) {
            selectors["message_input"] =
              `[contenteditable='true'].${classes.join(".")}`;
          } else {
            selectors["message_input"] = pattern;
          }
          break;
        }
      }
    }

    // Fallback: regular input field
    if (!selectors["message_input"]) {
      const inputPatterns = [
        "input[placeholder*='message' i]",
        "input[placeholder*='type' i]",
        "input[name*='message' i]",
        "input[type='text'][class*='message' i]",
      ];

      for (const pattern of inputPatterns) {
        const el = document.querySelector(pattern);
        if (el) {
          const classes = Array.from(el.classList);
          if (classes.length > 0) {
            selectors["message_input"] =
              `input.${classes.join(".")}`;
          } else {
            selectors["message_input"] = pattern;
          }
          break;
        }
      }
    }

    // --- Send button ---
    const sendKeywords = ["send", "submit"];
    const buttons = document.querySelectorAll(
      "button, [role='button'], input[type='submit']",
    );

    for (const btn of buttons) {
      const text = (btn.textContent ?? "").trim().toLowerCase();
      const ariaLabel = (
        btn.getAttribute("aria-label") ?? ""
      ).toLowerCase();
      const title = (btn.getAttribute("title") ?? "").toLowerCase();
      const combined = `${text} ${ariaLabel} ${title}`;

      const isMatch = sendKeywords.some((kw) =>
        combined.includes(kw),
      );
      if (!isMatch) continue;

      const id = btn.id;
      if (id) {
        selectors["send_button"] = `#${id}`;
        break;
      }
      const classes = Array.from(btn.classList);
      if (classes.length > 0) {
        selectors["send_button"] =
          `${btn.tagName.toLowerCase()}.${classes.join(".")}`;
        break;
      }
    }

    // Fallback: button with send icon
    if (!selectors["send_button"]) {
      const iconButtonPatterns = [
        "button svg[class*='send']",
        "button i[class*='send']",
        "[role='button'] svg[class*='send']",
      ];

      for (const pattern of iconButtonPatterns) {
        const icon = document.querySelector(pattern);
        if (!icon) continue;
        let parent: Element | null = icon.parentElement;
        for (let i = 0; i < 3 && parent; i++) {
          const tag = parent.tagName.toLowerCase();
          if (
            tag === "button" ||
            parent.getAttribute("role") === "button"
          ) {
            const classes = Array.from(parent.classList);
            if (classes.length > 0) {
              selectors["send_button"] =
                `${tag}.${classes.join(".")}`;
            } else if (parent.id) {
              selectors["send_button"] = `#${parent.id}`;
            }
            break;
          }
          parent = parent.parentElement;
        }
        if (selectors["send_button"]) break;
      }
    }

    // --- Confirmation indicator ---
    // Look for elements that appear after a message is sent:
    // success toasts, "sent" badges, checkmarks, timestamp on sent msg
    const confirmPatterns = [
      "[class*='success']",
      "[class*='sent']",
      "[class*='delivered']",
      "[class*='toast']",
      "[class*='notification']",
      "[class*='confirm']",
      "[class*='check']",
      "[role='alert']",
      "[role='status']",
    ];

    for (const pattern of confirmPatterns) {
      const el = document.querySelector(pattern);
      if (el) {
        const classes = Array.from(el.classList);
        if (classes.length > 0) {
          selectors["confirmation_indicator"] =
            `.${classes.join(".")}`;
        } else {
          selectors["confirmation_indicator"] = pattern;
        }
        break;
      }
    }

    return selectors;
  });

  return {
    dm_button: dmButtonSelector,
    message_input: pageSelectors["message_input"] ?? "",
    send_button: pageSelectors["send_button"] ?? "",
    confirmation_indicator:
      pageSelectors["confirmation_indicator"] ?? "",
  };
}

/**
 * Write discovered DM selectors to `config/selectors.json`,
 * preserving existing scraper selectors.
 */
function writeDmSelectorsConfig(dmSelectors: DmSelectors): void {
  let existing: Record<string, unknown> = {};
  try {
    const raw = readFileSync(SELECTORS_PATH, "utf-8");
    existing = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    // File missing or invalid — start fresh
  }

  const config = {
    scraper: existing["scraper"] ?? {
      profile_list_container: "",
      profile_card: "",
      username: "",
      profile_url: "",
      bio: "",
      tags: "",
    },
    dm: dmSelectors,
  };

  writeFileSync(
    SELECTORS_PATH,
    JSON.stringify(config, null, 2) + "\n",
    "utf-8",
  );
  console.log(`[recon-dm] DM selectors written to ${SELECTORS_PATH}`);
}

function emptyDmSelectors(): DmSelectors {
  return {
    dm_button: "",
    message_input: "",
    send_button: "",
    confirmation_indicator: "",
  };
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
      load_more_button: "",
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
      load_more_button: string;
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
    load_more_button: "",
  };
}
