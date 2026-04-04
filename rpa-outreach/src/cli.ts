#!/usr/bin/env node

import { Command } from "commander";
import { getPool, closePool } from "./db.js";
import { reconScraperPages, reconDmPages } from "./recon.js";
import { scrapeAll } from "./scrape.js";
import { filterProspects } from "./filter.js";
import { sendMessages } from "./send.js";
import { printStatusReport } from "./status.js";
import { login, validateSession } from "./auth.js";

const program = new Command();

program
  .name("rpa-outreach")
  .description(
    "DoraHacks hackathon recruitment outreach — "
    + "scrape, filter, and DM participants",
  )
  .version("0.1.0");

program
  .command("recon")
  .description(
    "Discover CSS selectors from DoraHacks pages "
    + "(saves HTML + screenshots to recon/)",
  )
  .option(
    "--scraper-only",
    "Only run scraper page recon (skip DM pages)",
  )
  .option(
    "--dm-only",
    "Only run DM page recon (skip scraper pages)",
  )
  .option(
    "--profile-url <urls...>",
    "Profile URL(s) for DM recon (required for --dm-only)",
  )
  .option(
    "--account <name>",
    "Account name for session storage (default: \"default\")",
  )
  .action(async (opts: {
    scraperOnly?: boolean;
    dmOnly?: boolean;
    profileUrl?: string[];
    account?: string;
  }) => {
    if (!opts.dmOnly) {
      console.log("[recon] Discovering scraper selectors...");
      await reconScraperPages(undefined, opts.account);
    }
    if (!opts.scraperOnly) {
      console.log("[recon] Discovering DM selectors...");
      await reconDmPages(opts.profileUrl, opts.account);
    }
    console.log("[recon] Done.");
  });

program
  .command("scrape")
  .description(
    "Scrape DoraHacks hackathon participant profiles",
  )
  .option(
    "--account <name>",
    "Account name for session storage (default: \"default\")",
  )
  .action(async (opts: { account?: string }) => {
    const result = await scrapeAll(opts.account);
    console.log(
      `\n[scrape] Complete: ${result.totalInserted} new profiles `
      + `from ${result.hackathons} hackathons`,
    );
    await closePool();
  });

program
  .command("filter")
  .description(
    "Score and tag scraped prospects by relevance",
  )
  .action(async () => {
    const pool = await getPool();
    const stats = await filterProspects(pool);
    console.log(
      `\n[filter] Processed ${stats.processed} prospects`,
    );
    for (const [category, count] of Object.entries(
      stats.byCategory,
    )) {
      console.log(`  ${category}: ${count}`);
    }
    await closePool();
  });

program
  .command("send")
  .description(
    "Send DMs to filtered prospects via DoraHacks messaging",
  )
  .requiredOption(
    "--listing-url <url>",
    "Canon listing URL to include in messages",
  )
  .requiredOption(
    "--hackathon-name <name>",
    "Hackathon name for message personalization",
  )
  .option("--live", "Send messages for real (default is dry-run)")
  .option("--dry-run", "Preview messages without sending (default)")
  .option(
    "--batch-limit <n>",
    "Max messages per session",
    parseInt,
  )
  .option(
    "--rate-cap <n>",
    "Max messages per hour",
    parseInt,
  )
  .option(
    "--account <name>",
    "Account name for session storage (default: \"default\")",
  )
  .action(
    async (opts: {
      listingUrl: string;
      hackathonName: string;
      live?: boolean;
      dryRun?: boolean;
      batchLimit?: number;
      rateCap?: number;
      account?: string;
    }) => {
      const live = opts.live === true && opts.dryRun !== true;
      const pool = await getPool();

      console.log(
        `[send] Mode: ${live ? "LIVE" : "DRY-RUN"}`,
      );

      const sendOpts: Parameters<typeof sendMessages>[1] = {
        live,
        listingUrl: opts.listingUrl,
        hackathonName: opts.hackathonName,
      };
      if (opts.account !== undefined) {
        sendOpts.account = opts.account;
      }
      if (opts.batchLimit !== undefined) {
        sendOpts.batchLimit = opts.batchLimit;
      }
      if (opts.rateCap !== undefined) {
        sendOpts.rateCapPerHour = opts.rateCap;
      }

      const stats = await sendMessages(pool, sendOpts);

      console.log(
        `\n[send] Complete: ${stats.sent} sent, `
        + `${stats.failed} failed, ${stats.skipped} skipped`,
      );
      if (stats.stoppedReason) {
        console.log(`[send] Stopped: ${stats.stoppedReason}`);
      }

      await closePool();
    },
  );

program
  .command("status")
  .description("Show pipeline status report")
  .action(async () => {
    const pool = await getPool();
    await printStatusReport(pool);
    await closePool();
  });

program
  .command("login")
  .description(
    "Open Chromium for manual DoraHacks login — "
    + "saves session to auth/<account>/storage-state.json",
  )
  .option(
    "--account <name>",
    "Account name for session storage (default: \"default\")",
  )
  .option(
    "--validate",
    "Validate an existing session instead of logging in",
  )
  .action(
    async (opts: { account?: string; validate?: boolean }) => {
      if (opts.validate) {
        const valid = await validateSession(opts.account);
        const name = opts.account ?? "default";
        if (valid) {
          console.log(
            `[login] Session for "${name}" is valid.`,
          );
        } else {
          console.log(
            `[login] Session for "${name}" is invalid `
            + `or missing.`,
          );
          process.exitCode = 1;
        }
        return;
      }

      await login(opts.account);
    },
  );

program.parse();
