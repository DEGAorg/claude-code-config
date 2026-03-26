import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  SelectorsConfig,
  HackathonEntry,
  DefaultsConfig,
  AppConfig,
} from "./types.js";

const PROJECT_ROOT = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
);

const CONFIG_DIR = resolve(PROJECT_ROOT, "config");

function readJson<T>(filename: string): T {
  const filepath = resolve(CONFIG_DIR, filename);
  const raw = readFileSync(filepath, "utf-8");
  return JSON.parse(raw) as T;
}

export function loadSelectors(): SelectorsConfig {
  return readJson<SelectorsConfig>("selectors.json");
}

export function loadHackathons(): HackathonEntry[] {
  return readJson<HackathonEntry[]>("hackathons.json");
}

export function loadDefaults(): DefaultsConfig {
  return readJson<DefaultsConfig>("defaults.json");
}

export function loadConfig(): AppConfig {
  return {
    selectors: loadSelectors(),
    hackathons: loadHackathons(),
    defaults: loadDefaults(),
  };
}
