import { describe, it, expect } from "vitest";
import {
  loadTemplate,
  loadAllTemplates,
  replaceTokens,
  selectVariant,
  renderMessage,
} from "../src/templates.js";
import type { TemplateVariant, TemplateTokens } from "../src/templates.js";

// ---------- loadTemplate ----------

describe("loadTemplate", () => {
  it("loads generic template", () => {
    const content = loadTemplate("generic");
    expect(content).toContain("{name}");
    expect(content).toContain("{hackathon_name}");
    expect(content).toContain("{listing_url}");
  });

  it("loads crypto template", () => {
    const content = loadTemplate("crypto");
    expect(content.length).toBeGreaterThan(0);
    expect(content).toContain("{name}");
  });

  it("loads ai-ml template", () => {
    const content = loadTemplate("ai-ml");
    expect(content.length).toBeGreaterThan(0);
    expect(content).toContain("{name}");
  });

  it("loads sports template", () => {
    const content = loadTemplate("sports");
    expect(content.length).toBeGreaterThan(0);
    expect(content).toContain("{name}");
  });
});

// ---------- loadAllTemplates ----------

describe("loadAllTemplates", () => {
  it("returns a map with all four variants", () => {
    const templates = loadAllTemplates();
    const variants: TemplateVariant[] = [
      "generic",
      "crypto",
      "ai-ml",
      "sports",
    ];
    for (const v of variants) {
      expect(templates.has(v)).toBe(true);
      expect(templates.get(v)?.length).toBeGreaterThan(0);
    }
  });

  it("does not include non-.txt files", () => {
    const templates = loadAllTemplates();
    expect(templates.size).toBe(4);
  });
});

// ---------- replaceTokens ----------

describe("replaceTokens", () => {
  const tokens: TemplateTokens = {
    name: "Alice",
    hackathon_name: "ETHGlobal 2026",
    listing_url: "https://dorahacks.io/listing/123",
  };

  it("replaces all token placeholders", () => {
    const template = "Hi {name}, check out {hackathon_name} at {listing_url}!";
    const result = replaceTokens(template, tokens);
    expect(result).toBe(
      "Hi Alice, check out ETHGlobal 2026 at https://dorahacks.io/listing/123!",
    );
  });

  it("replaces multiple occurrences of the same token", () => {
    const template = "{name} and {name} again";
    const result = replaceTokens(template, tokens);
    expect(result).toBe("Alice and Alice again");
  });

  it("leaves text without tokens unchanged", () => {
    const template = "No tokens here";
    const result = replaceTokens(template, tokens);
    expect(result).toBe("No tokens here");
  });

  it("handles empty token values", () => {
    const result = replaceTokens("Hi {name}!", {
      name: "",
      hackathon_name: "H",
      listing_url: "U",
    });
    expect(result).toBe("Hi !");
  });
});

// ---------- selectVariant ----------

describe("selectVariant", () => {
  it("maps crypto interest to crypto variant", () => {
    expect(selectVariant("crypto")).toBe("crypto");
  });

  it("maps blockchain to crypto variant", () => {
    expect(selectVariant("blockchain")).toBe("crypto");
  });

  it("maps defi to crypto variant", () => {
    expect(selectVariant("defi")).toBe("crypto");
  });

  it("maps web3 to crypto variant", () => {
    expect(selectVariant("web3")).toBe("crypto");
  });

  it("maps ai/ml to ai-ml variant", () => {
    expect(selectVariant("ai/ml")).toBe("ai-ml");
  });

  it("maps ai to ai-ml variant", () => {
    expect(selectVariant("ai")).toBe("ai-ml");
  });

  it("maps ml to ai-ml variant", () => {
    expect(selectVariant("ml")).toBe("ai-ml");
  });

  it("maps machine learning to ai-ml variant", () => {
    expect(selectVariant("machine learning")).toBe("ai-ml");
  });

  it("maps artificial intelligence to ai-ml variant", () => {
    expect(selectVariant("artificial intelligence")).toBe("ai-ml");
  });

  it("maps sports to sports variant", () => {
    expect(selectVariant("sports")).toBe("sports");
  });

  it("maps sports tech to sports variant", () => {
    expect(selectVariant("sports tech")).toBe("sports");
  });

  it("maps esports to sports variant", () => {
    expect(selectVariant("esports")).toBe("sports");
  });

  it("falls back to generic for unknown interests", () => {
    expect(selectVariant("cooking")).toBe("generic");
    expect(selectVariant("")).toBe("generic");
    expect(selectVariant("random")).toBe("generic");
  });

  it("is case insensitive", () => {
    expect(selectVariant("CRYPTO")).toBe("crypto");
    expect(selectVariant("AI/ML")).toBe("ai-ml");
    expect(selectVariant("Sports")).toBe("sports");
  });

  it("trims whitespace", () => {
    expect(selectVariant("  crypto  ")).toBe("crypto");
    expect(selectVariant(" ai ")).toBe("ai-ml");
  });
});

// ---------- renderMessage ----------

describe("renderMessage", () => {
  const tokens: TemplateTokens = {
    name: "Bob",
    hackathon_name: "Canon Hackathon",
    listing_url: "https://dorahacks.io/listing/456",
  };

  it("renders a crypto message with tokens replaced", () => {
    const msg = renderMessage("crypto", tokens);
    expect(msg).toContain("Bob");
    expect(msg).toContain("Canon Hackathon");
    expect(msg).toContain("https://dorahacks.io/listing/456");
    expect(msg).not.toContain("{name}");
    expect(msg).not.toContain("{hackathon_name}");
    expect(msg).not.toContain("{listing_url}");
  });

  it("renders a generic message for unknown interest", () => {
    const msg = renderMessage("unknown-category", tokens);
    expect(msg).toContain("Bob");
    expect(msg).not.toContain("{name}");
  });

  it("selects the correct variant for ai-ml", () => {
    const msg = renderMessage("ai/ml", tokens);
    expect(msg.toLowerCase()).toContain("ai");
  });

  it("selects the correct variant for sports", () => {
    const msg = renderMessage("sports", tokens);
    expect(msg.toLowerCase()).toContain("sports");
  });
});
