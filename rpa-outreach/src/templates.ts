import { readFileSync, readdirSync } from "node:fs";
import { resolve, dirname, basename, extname } from "node:path";
import { fileURLToPath } from "node:url";

const PROJECT_ROOT = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
);

const TEMPLATES_DIR = resolve(PROJECT_ROOT, "templates");

export type TemplateVariant = "generic" | "crypto" | "ai-ml" | "sports";

export interface TemplateTokens {
  name: string;
  hackathon_name: string;
  listing_url: string;
}

const INTEREST_TO_VARIANT: Record<string, TemplateVariant> = {
  crypto: "crypto",
  blockchain: "crypto",
  defi: "crypto",
  web3: "crypto",
  "ai/ml": "ai-ml",
  ai: "ai-ml",
  ml: "ai-ml",
  "machine learning": "ai-ml",
  "artificial intelligence": "ai-ml",
  sports: "sports",
  "sports tech": "sports",
  esports: "sports",
};

export function loadTemplate(variant: TemplateVariant): string {
  const filepath = resolve(TEMPLATES_DIR, `${variant}.txt`);
  return readFileSync(filepath, "utf-8");
}

export function loadAllTemplates(): Map<TemplateVariant, string> {
  const templates = new Map<TemplateVariant, string>();
  const files = readdirSync(TEMPLATES_DIR);

  for (const file of files) {
    if (extname(file) !== ".txt") {
      continue;
    }
    const variant = basename(file, ".txt") as TemplateVariant;
    templates.set(variant, readFileSync(
      resolve(TEMPLATES_DIR, file),
      "utf-8",
    ));
  }

  return templates;
}

export function replaceTokens(
  template: string,
  tokens: TemplateTokens,
): string {
  return template
    .replace(/{name}/g, tokens.name)
    .replace(/{hackathon_name}/g, tokens.hackathon_name)
    .replace(/{listing_url}/g, tokens.listing_url);
}

export function selectVariant(interest: string): TemplateVariant {
  const normalized = interest.toLowerCase().trim();
  return INTEREST_TO_VARIANT[normalized] ?? "generic";
}

export function renderMessage(
  interest: string,
  tokens: TemplateTokens,
): string {
  const variant = selectVariant(interest);
  const template = loadTemplate(variant);
  return replaceTokens(template, tokens);
}
