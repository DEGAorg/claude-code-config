#!/usr/bin/env node

import { Command } from "commander";
import { getPool, closePool } from "./db.js";
import { reconScraperPages, reconDmPages } from "./recon.js";
import { scrapeAll } from "./scrape.js";
import { filterProspects } from "./filter.js";
import { sendMessages } from "./send.js";
import { printStatusReport } from "./status.js";

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
  .action(async (opts: {
    scraperOnly?: boolean;
    dmOnly?: boolean;
    profileUrl?: string[];
  }) => {
    if (!opts.dmOnly) {
      console.log("[recon] Discovering scraper selectors...");
      await reconScraperPages();
    }
    if (!opts.scraperOnly) {
      console.log("[recon] Discovering DM selectors...");
      await reconDmPages(opts.profileUrl);
    }
    console.log("[recon] Done.");
  });

program
  .command("scrape")
  .description(
    "Scrape DoraHacks hackathon participant profiles",
  )
  .action(async () => {
    const result = await scrapeAll();
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
  .action(
    async (opts: {
      listingUrl: string;
      hackathonName: string;
      live?: boolean;
      dryRun?: boolean;
      batchLimit?: number;
      rateCap?: number;
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

program.parse();
