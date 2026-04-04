import type { Page } from "playwright";
import type { DmSelectors } from "./types.js";
import type { DbPool, Prospect } from "./db.js";
import {
  claimNextProspect,
  updateStatusWithTimestamp,
  updateStatus,
} from "./db.js";
import { loadSession } from "./auth.js";
import { loadSelectors, loadDefaults } from "./config.js";
import { renderMessage, type TemplateTokens } from "./templates.js";

// ---------- Types ----------

export interface SendOptions {
  live: boolean;
  listingUrl: string;
  hackathonName: string;
  batchLimit?: number;
  rateCapPerHour?: number;
  delayMinMs?: number;
  delayMaxMs?: number;
  account?: string;
}

export interface SendStats {
  attempted: number;
  sent: number;
  skipped: number;
  failed: number;
  stoppedReason: string | null;
}

// ---------- Helpers ----------

function randomDelay(minMs: number, maxMs: number): number {
  return Math.floor(Math.random() * (maxMs - minMs + 1)) + minMs;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

/**
 * Detect captcha, block, or rate limit indicators on the page.
 * Returns a description of the issue or null if the page looks normal.
 */
async function detectBlocker(page: Page): Promise<string | null> {
  const blockerPatterns = [
    "captcha",
    "rate limit",
    "too many requests",
    "blocked",
    "access denied",
    "verify you are human",
    "unusual activity",
    "try again later",
  ];

  const bodyText = await page
    .evaluate(() => document.body?.innerText?.toLowerCase() ?? "")
    .catch(() => "");

  for (const pattern of blockerPatterns) {
    if (bodyText.includes(pattern)) {
      return `Detected blocker: "${pattern}" found on page`;
    }
  }

  return null;
}

/**
 * Navigate to a profile's DM page and fill the message.
 * In dry-run mode, logs the message without sending.
 * In live mode, clicks the send button and waits for confirmation.
 */
async function sendOneMessage(
  page: Page,
  prospect: Prospect,
  message: string,
  selectors: DmSelectors,
  live: boolean,
): Promise<{ success: boolean; error?: string }> {
  try {
    await page.goto(prospect.profile_url, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(2000);

    const blocker = await detectBlocker(page);
    if (blocker) {
      return { success: false, error: blocker };
    }

    // Click DM button on profile
    const dmButton = page.locator(selectors.dm_button).first();
    const dmButtonVisible = await dmButton.isVisible().catch(() => false);
    if (!dmButtonVisible) {
      return {
        success: false,
        error: `DM button not found on profile: ${prospect.profile_url}`,
      };
    }

    await dmButton.click();
    await page.waitForTimeout(2000);

    // Fill message input
    const messageInput = page.locator(selectors.message_input).first();
    await messageInput.waitFor({ state: "visible", timeout: 10_000 });
    await messageInput.click();
    await messageInput.fill(message);

    if (!live) {
      console.log(
        `[dry-run] Would send to ${prospect.username}:\n${message}\n`,
      );
      return { success: true };
    }

    // Live mode: click send
    const sendButton = page.locator(selectors.send_button).first();
    await sendButton.waitFor({ state: "visible", timeout: 5_000 });
    await sendButton.click();

    // Wait for confirmation indicator
    if (selectors.confirmation_indicator) {
      try {
        await page
          .locator(selectors.confirmation_indicator)
          .first()
          .waitFor({ state: "visible", timeout: 10_000 });
      } catch {
        console.warn(
          `[send] Confirmation indicator not found for ${prospect.username} — message may or may not have sent`,
        );
      }
    }

    console.log(`[send] Sent DM to ${prospect.username}`);
    return { success: true };
  } catch (err: unknown) {
    const errorMsg =
      err instanceof Error ? err.message : "Unknown error during send";
    return { success: false, error: errorMsg };
  }
}

// ---------- Rate limiter ----------

class RateLimiter {
  private timestamps: number[] = [];
  private readonly maxPerHour: number;

  constructor(maxPerHour: number) {
    this.maxPerHour = maxPerHour;
  }

  canProceed(): boolean {
    const now = Date.now();
    const oneHourAgo = now - 3_600_000;
    this.timestamps = this.timestamps.filter((t) => t > oneHourAgo);
    return this.timestamps.length < this.maxPerHour;
  }

  record(): void {
    this.timestamps.push(Date.now());
  }

  waitTimeMs(): number {
    if (this.canProceed()) {
      return 0;
    }
    const oldest = this.timestamps[0];
    if (oldest === undefined) {
      return 0;
    }
    return oldest + 3_600_000 - Date.now() + 1000;
  }
}

// ---------- Main sender ----------

export async function sendMessages(
  pool: DbPool,
  options: SendOptions,
): Promise<SendStats> {
  const defaults = loadDefaults();
  const selectors = loadSelectors();

  const batchLimit = options.batchLimit ?? defaults.batch_limit_per_session;
  const rateCapPerHour =
    options.rateCapPerHour ?? defaults.rate_cap_per_hour;
  const delayMinMs = options.delayMinMs ?? defaults.delay_min_ms;
  const delayMaxMs = options.delayMaxMs ?? defaults.delay_max_ms;

  const stats: SendStats = {
    attempted: 0,
    sent: 0,
    skipped: 0,
    failed: 0,
    stoppedReason: null,
  };

  console.log(
    `[send] Claiming prospects one-at-a-time. ` +
      `Batch limit: ${batchLimit}. Mode: ${options.live ? "LIVE" : "DRY-RUN"}`,
  );

  const { browser, context } = await loadSession();
  const page = await context.newPage();
  const rateLimiter = new RateLimiter(rateCapPerHour);

  try {
    while (stats.attempted < batchLimit) {
      if (!rateLimiter.canProceed()) {
        const waitMs = rateLimiter.waitTimeMs();
        stats.stoppedReason =
          `Rate cap reached (${rateCapPerHour}/hr). ` +
          `Would need to wait ${Math.ceil(waitMs / 1000)}s`;
        console.log(`[send] ${stats.stoppedReason}`);
        break;
      }

      const prospect = await claimNextProspect(
        pool,
        "filtered",
        "queued",
      );
      if (!prospect) {
        if (stats.attempted === 0) {
          console.log("[send] No filtered prospects to message.");
        }
        break;
      }

      const interestTag = prospect.interest_tag ?? "generic";
      const tokens: TemplateTokens = {
        name: prospect.display_name || prospect.username,
        hackathon_name: options.hackathonName,
        listing_url: options.listingUrl,
      };
      const message = renderMessage(interestTag, tokens);

      stats.attempted += 1;
      const result = await sendOneMessage(
        page,
        prospect,
        message,
        selectors.dm,
        options.live,
      );

      if (result.success) {
        stats.sent += 1;
        rateLimiter.record();

        if (options.live) {
          const timestamp = new Date().toISOString();
          await updateStatusWithTimestamp(
            pool,
            prospect.id,
            "messaged",
            timestamp,
          );
        }
      } else if (result.error) {
        const blocker = await detectBlocker(page);
        if (blocker) {
          stats.stoppedReason = `Stop-on-error: ${result.error}`;
          stats.failed += 1;
          await updateStatus(pool, prospect.id, "failed");
          console.error(
            `[send] STOPPING — blocker detected: ${result.error}`,
          );
          break;
        }

        console.warn(
          `[send] Failed for ${prospect.username}: ${result.error}`,
        );
        stats.failed += 1;
        await updateStatus(pool, prospect.id, "skipped");
      }

      // Randomized delay between messages
      if (stats.attempted < batchLimit) {
        const delay = randomDelay(delayMinMs, delayMaxMs);
        console.log(
          `[send] Waiting ${(delay / 1000).toFixed(0)}s before next message...`,
        );
        await sleep(delay);
      }
    }
  } finally {
    await page.close();
    await context.close();
    await browser.close();
  }

  if (stats.attempted === 0) {
    // Already logged "No filtered prospects" above
  } else {
    console.log(
      `[send] Done. Attempted: ${stats.attempted}, ` +
        `Sent: ${stats.sent}, Skipped: ${stats.skipped}, ` +
        `Failed: ${stats.failed}`,
    );
    if (stats.stoppedReason) {
      console.log(`[send] Stopped early: ${stats.stoppedReason}`);
    }
  }

  return stats;
}
