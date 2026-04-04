import type { Pool } from "@neondatabase/serverless";

export type DbPool = Pool;

export type ProspectStatus =
  | "scraped"
  | "filtered"
  | "queued"
  | "messaged"
  | "replied"
  | "skipped"
  | "failed";

export interface Prospect {
  id: number;
  username: string;
  display_name: string;
  profile_url: string;
  bio: string;
  tags: string;
  source_hackathon: string;
  relevance_score: number | null;
  interest_tag: string | null;
  status: ProspectStatus;
  messaged_at: string | null;
  created_at: string;
  updated_at: string;
}

export type ProspectInsert = Pick<
  Prospect,
  | "username"
  | "profile_url"
  | "display_name"
  | "bio"
  | "tags"
  | "source_hackathon"
>;

export type ProspectUpsert = ProspectInsert;

export interface ScraperSelectors {
  profile_list_container: string;
  profile_card: string;
  username: string;
  profile_url: string;
  bio: string;
  tags: string;
  load_more_button: string;
}

export interface DmSelectors {
  dm_button: string;
  message_input: string;
  send_button: string;
  confirmation_indicator: string;
}

export interface SelectorsConfig {
  scraper: ScraperSelectors;
  dm: DmSelectors;
}

export interface HackathonEntry {
  url: string;
  name: string;
}

export interface DefaultsConfig {
  delay_min_ms: number;
  delay_max_ms: number;
  rate_cap_per_hour: number;
  batch_limit_per_session: number;
  scrape_delay_ms: number;
}

export interface AppConfig {
  selectors: SelectorsConfig;
  hackathons: HackathonEntry[];
  defaults: DefaultsConfig;
}
