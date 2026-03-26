export const ProspectStatus = {
  scraped: "scraped",
  filtered: "filtered",
  queued: "queued",
  messaged: "messaged",
  replied: "replied",
  skipped: "skipped",
  failed: "failed",
} as const;

export type ProspectStatus =
  (typeof ProspectStatus)[keyof typeof ProspectStatus];

export interface Prospect {
  id: number;
  username: string;
  display_name: string;
  profile_url: string;
  bio: string;
  tags: string;
  source_hackathon: string;
  relevance_score: number;
  interest: string;
  status: ProspectStatus;
  messaged_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface ScraperSelectors {
  profile_list_container: string;
  profile_card: string;
  username: string;
  profile_url: string;
  bio: string;
  tags: string;
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
