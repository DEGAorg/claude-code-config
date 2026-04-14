/**
 * Help subcommand — reads canon/skills/*.md, formats by topic.
 *
 * Usage:
 *   canon-cli help                List all available skills
 *   canon-cli help <topic>        Show skill content for a topic
 */

import { readdir, readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { stripFormatFlags, writeError, writeSuccess } from "../output.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const SKILLS_DIR = resolve(HERE, "../../skills");

interface SkillFrontmatter {
  name: string;
  description: string;
  version: string;
  domain: string;
  requires: string[];
  tools: string[];
}

interface SkillSummary {
  name: string;
  description: string;
  domain: string;
}

interface SkillDetail {
  name: string;
  description: string;
  domain: string;
  version: string;
  requires: string[];
  tools: string[];
  content: string;
}

/**
 * Parse YAML frontmatter from a markdown file.
 *
 * Handles the simple key: value and key: [array] format
 * used in canon skill files. Returns null if no frontmatter found.
 */
export function parseFrontmatter(
  raw: string,
): { meta: SkillFrontmatter; body: string } | null {
  if (!raw.startsWith("---\n")) return null;

  const endIdx = raw.indexOf("\n---\n", 4);
  if (endIdx === -1) return null;

  const yamlBlock = raw.slice(4, endIdx);
  const body = raw.slice(endIdx + 5).trim();

  const meta: SkillFrontmatter = {
    name: "",
    description: "",
    version: "",
    domain: "",
    requires: [],
    tools: [],
  };

  for (const line of yamlBlock.split("\n")) {
    const match = /^(\w+):\s*(.*)$/.exec(line);
    if (!match?.[1] || match[2] === undefined) continue;

    const key = match[1];
    const val = match[2].trim();

    if (key === "requires" || key === "tools") {
      const arrayMatch = /^\[([^\]]*)\]$/.exec(val);
      if (arrayMatch && arrayMatch[1] !== undefined) {
        const inner = arrayMatch[1].trim();
        meta[key] =
          inner === ""
            ? []
            : inner.split(",").map((s) => s.trim());
      }
    } else if (
      key === "name" ||
      key === "description" ||
      key === "version" ||
      key === "domain"
    ) {
      meta[key] = val;
    }
  }

  return { meta, body };
}

async function loadSkillFiles(): Promise<
  Array<{ filename: string; raw: string }>
> {
  const entries = await readdir(SKILLS_DIR);
  const mdFiles = entries
    .filter((f) => f.endsWith(".md"))
    .sort();

  const results: Array<{ filename: string; raw: string }> = [];
  for (const filename of mdFiles) {
    const raw = await readFile(
      join(SKILLS_DIR, filename),
      "utf-8",
    );
    results.push({ filename, raw });
  }
  return results;
}

async function handleList(
  rawArgs: readonly string[],
): Promise<void> {
  const files = await loadSkillFiles();
  const skills: SkillSummary[] = [];

  for (const { filename, raw } of files) {
    const parsed = parseFrontmatter(raw);
    if (parsed) {
      skills.push({
        name: parsed.meta.name,
        description: parsed.meta.description,
        domain: parsed.meta.domain,
      });
    } else {
      // Files without frontmatter: use filename as name
      const name = filename.replace(/\.md$/, "");
      skills.push({
        name,
        description: "",
        domain: "",
      });
    }
  }

  writeSuccess({ skills }, rawArgs);
}

async function handleTopic(
  topic: string,
  rawArgs: readonly string[],
): Promise<void> {
  const files = await loadSkillFiles();

  for (const { filename, raw } of files) {
    const parsed = parseFrontmatter(raw);
    const name = parsed
      ? parsed.meta.name
      : filename.replace(/\.md$/, "");

    if (name === topic) {
      if (parsed) {
        const detail: SkillDetail = {
          name: parsed.meta.name,
          description: parsed.meta.description,
          domain: parsed.meta.domain,
          version: parsed.meta.version,
          requires: parsed.meta.requires,
          tools: parsed.meta.tools,
          content: parsed.body,
        };
        writeSuccess(detail, rawArgs);
      } else {
        writeSuccess(
          { name, description: "", content: raw },
          rawArgs,
        );
      }
      return;
    }
  }

  const allNames = files.map(({ filename, raw }) => {
    const parsed = parseFrontmatter(raw);
    return parsed
      ? parsed.meta.name
      : filename.replace(/\.md$/, "");
  });

  writeError(
    `Unknown topic "${topic}". ` +
      `Available: ${allNames.join(", ")}`,
    rawArgs,
  );
}

export async function run(args: string[]): Promise<void> {
  const cleaned = stripFormatFlags(args);
  const topic = cleaned[0];

  if (!topic) {
    await handleList(args);
    return;
  }

  await handleTopic(topic, args);
}
