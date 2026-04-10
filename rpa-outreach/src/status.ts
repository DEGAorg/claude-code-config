import { countByStatus, getPool, type ProspectStatus } from "./db.js";
import type { DbPool } from "./db.js";

interface StatusRow {
  label: string;
  status: ProspectStatus;
}

const PIPELINE_STAGES: StatusRow[] = [
  { label: "Scraped", status: "scraped" },
  { label: "Filtered", status: "filtered" },
  { label: "Queued", status: "queued" },
  { label: "Messaged", status: "messaged" },
  { label: "Replied", status: "replied" },
  { label: "Skipped", status: "skipped" },
  { label: "Failed", status: "failed" },
];

export async function printStatusReport(
  pool?: DbPool,
): Promise<void> {
  const p = pool ?? await getPool();
  const counts = await countByStatus(p);
  let total = 0;
  for (const stage of PIPELINE_STAGES) {
    total += counts[stage.status];
  }

  const separator = "─".repeat(30);

  console.log("");
  console.log("  Pipeline Status Report");
  console.log(`  ${separator}`);

  for (const stage of PIPELINE_STAGES) {
    const count = counts[stage.status];
    const pct = total > 0 ? ((count / total) * 100).toFixed(1) : "0.0";
    const bar = "█".repeat(
      Math.round(total > 0 ? (count / total) * 20 : 0),
    );
    console.log(
      `  ${stage.label.padEnd(10)} ${String(count).padStart(6)}  ${pct.padStart(5)}%  ${bar}`,
    );
  }

  console.log(`  ${separator}`);
  console.log(`  ${"Total".padEnd(10)} ${String(total).padStart(6)}`);
  console.log("");
}
