#!/usr/bin/env node

import { Command } from "commander";
import { getDb, closeDb } from "./db.js";
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
  .action(async (opts: { scraperOnly?: boolean; dmOnly?: boolean }) => {
    if (!opts.dmOnly) {
      console.log("[recon] Discovering scraper selectors...");
      await reconScraperPages();
    }
    if (!opts.scraperOnly) {
      console.log("[recon] Discovering DM selectors...");
      await reconDmPages();
    }
    console.log("[recon] Done.");
  });

program
  .command("scrape")
  .description(
    "Scrape DoraHacks hackathon participant profiles",
  )
  .option(
    "--db <path>",
    "SQLite database path",
    "outreach.db",
  )
  .action(async (opts: { db: string }) => {
    const result = await scrapeAll(opts.db);
    console.log(
      `\n[scrape] Complete: ${result.totalInserted} new profiles `
      + `from ${result.hackathons} hackathons`,
    );
  });

program
  .command("filter")
  .description(
    "Score and tag scraped prospects by relevance",
  )
  .option(
    "--db <path>",
    "SQLite database path",
    "outreach.db",
  )
  .action((opts: { db: string }) => {
    const db = getDb(opts.db);
    const stats = filterProspects(db);
    console.log(
      `\n[filter] Processed ${stats.processed} prospects`,
    );
    for (const [category, count] of Object.entries(
      stats.byCategory,
    )) {
      console.log(`  ${category}: ${count}`);
    }
    closeDb();
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
    "--db <path>",
    "SQLite database path",
    "outreach.db",
  )
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
      db: string;
      batchLimit?: number;
      rateCap?: number;
    }) => {
      const live = opts.live === true && opts.dryRun !== true;
      const db = getDb(opts.db);

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

      const stats = await sendMessages(db, sendOpts);

      console.log(
        `\n[send] Complete: ${stats.sent} sent, `
        + `${stats.failed} failed, ${stats.skipped} skipped`,
      );
      if (stats.stoppedReason) {
        console.log(`[send] Stopped: ${stats.stoppedReason}`);
      }

      closeDb();
    },
  );

program
  .command("status")
  .description("Show pipeline status report")
  .option(
    "--db <path>",
    "SQLite database path",
    "outreach.db",
  )
  .action((opts: { db: string }) => {
    const db = getDb(opts.db);
    printStatusReport(db);
    closeDb();
  });

program.parse();
