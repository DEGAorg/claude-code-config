import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from "vitest";

vi.mock("node:fs/promises", () => ({
  readdir: vi.fn(),
  readFile: vi.fn(),
}));

const fsMock = await import("node:fs/promises");
const readdir = vi.mocked(fsMock.readdir);
const readFile = vi.mocked(fsMock.readFile);

// Capture stdout/stderr writes
let stdoutData: string;
let stderrData: string;

const originalStdoutWrite = process.stdout.write.bind(process.stdout);
const originalStderrWrite = process.stderr.write.bind(process.stderr);

beforeEach(() => {
  stdoutData = "";
  stderrData = "";

  process.stdout.write = ((chunk: string) => {
    stdoutData += chunk;
    return true;
  }) as typeof process.stdout.write;

  process.stderr.write = ((chunk: string) => {
    stderrData += chunk;
    return true;
  }) as typeof process.stderr.write;

  process.exitCode = undefined;
});

afterEach(() => {
  process.stdout.write = originalStdoutWrite;
  process.stderr.write = originalStderrWrite;
  vi.clearAllMocks();
});

const SKILL_WITH_FRONTMATTER = `---
name: polymarket
description: Polymarket-specific knowledge
version: 1.0.0
domain: platform
requires: [prediction-markets]
tools: [canon-cli]
---

# Polymarket Platform Knowledge

## Core Knowledge
Platform mechanics and fee structure.`;

const SKILL_MINIMAL = `---
name: risk-management
description: Position sizing and exposure limits
version: 1.0.0
domain: risk
requires: []
tools: []
---

# Risk Management`;

const SKILL_NO_FRONTMATTER = `# Orchestrator Skill

The orchestrator runs plans.`;

const { run } = await import("../commands/help.js");
const { parseFrontmatter } = await import("../commands/help.js");

describe("parseFrontmatter", () => {
  it("parses valid frontmatter with arrays", () => {
    const result = parseFrontmatter(SKILL_WITH_FRONTMATTER);
    expect(result).not.toBeNull();
    expect(result?.meta.name).toBe("polymarket");
    expect(result?.meta.description).toBe(
      "Polymarket-specific knowledge",
    );
    expect(result?.meta.domain).toBe("platform");
    expect(result?.meta.version).toBe("1.0.0");
    expect(result?.meta.requires).toEqual(["prediction-markets"]);
    expect(result?.meta.tools).toEqual(["canon-cli"]);
  });

  it("parses empty arrays", () => {
    const result = parseFrontmatter(SKILL_MINIMAL);
    expect(result).not.toBeNull();
    expect(result?.meta.requires).toEqual([]);
    expect(result?.meta.tools).toEqual([]);
  });

  it("extracts body content after frontmatter", () => {
    const result = parseFrontmatter(SKILL_WITH_FRONTMATTER);
    expect(result?.body).toContain(
      "# Polymarket Platform Knowledge",
    );
    expect(result?.body).toContain("Platform mechanics");
  });

  it("returns null for files without frontmatter", () => {
    const result = parseFrontmatter(SKILL_NO_FRONTMATTER);
    expect(result).toBeNull();
  });

  it("returns null for empty string", () => {
    expect(parseFrontmatter("")).toBeNull();
  });

  it("returns null for malformed frontmatter (no closing ---)", () => {
    const broken = "---\nname: test\nno closing delimiter";
    expect(parseFrontmatter(broken)).toBeNull();
  });
});

describe("help list (no topic)", () => {
  it("lists all skills with frontmatter", async () => {
    readdir.mockResolvedValueOnce(
      ["polymarket.md", "risk-management.md"] as unknown as
        Awaited<ReturnType<typeof fsMock.readdir>>,
    );
    readFile
      .mockResolvedValueOnce(SKILL_WITH_FRONTMATTER)
      .mockResolvedValueOnce(SKILL_MINIMAL);

    await run([]);

    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: {
        skills: Array<{
          name: string;
          description: string;
          domain: string;
        }>;
      };
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data.skills).toHaveLength(2);
    expect(parsed.data.skills[0]).toEqual({
      name: "polymarket",
      description: "Polymarket-specific knowledge",
      domain: "platform",
    });
    expect(parsed.data.skills[1]).toEqual({
      name: "risk-management",
      description: "Position sizing and exposure limits",
      domain: "risk",
    });
  });

  it("handles skills without frontmatter", async () => {
    readdir.mockResolvedValueOnce(
      ["orchestrator.md"] as unknown as
        Awaited<ReturnType<typeof fsMock.readdir>>,
    );
    readFile.mockResolvedValueOnce(SKILL_NO_FRONTMATTER);

    await run([]);

    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: {
        skills: Array<{
          name: string;
          description: string;
          domain: string;
        }>;
      };
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data.skills[0]?.name).toBe("orchestrator");
    expect(parsed.data.skills[0]?.description).toBe("");
  });

  it("returns empty list when no skill files", async () => {
    readdir.mockResolvedValueOnce(
      [] as unknown as
        Awaited<ReturnType<typeof fsMock.readdir>>,
    );

    await run([]);

    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: { skills: unknown[] };
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data.skills).toHaveLength(0);
  });

  it("filters non-.md files from directory listing", async () => {
    readdir.mockResolvedValueOnce(
      ["polymarket.md", ".DS_Store", "readme.txt"] as unknown as
        Awaited<ReturnType<typeof fsMock.readdir>>,
    );
    readFile.mockResolvedValueOnce(SKILL_WITH_FRONTMATTER);

    await run([]);

    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: { skills: unknown[] };
    };
    expect(parsed.data.skills).toHaveLength(1);
    expect(readFile).toHaveBeenCalledTimes(1);
  });

  it("supports --pretty flag for listing", async () => {
    readdir.mockResolvedValueOnce(
      ["polymarket.md"] as unknown as
        Awaited<ReturnType<typeof fsMock.readdir>>,
    );
    readFile.mockResolvedValueOnce(SKILL_WITH_FRONTMATTER);

    await run(["--pretty"]);

    expect(stdoutData).toContain("\n");
    const parsed = JSON.parse(stdoutData) as { ok: boolean };
    expect(parsed.ok).toBe(true);
  });
});

describe("help <topic>", () => {
  it("shows full skill content for a known topic", async () => {
    readdir.mockResolvedValueOnce(
      ["polymarket.md"] as unknown as
        Awaited<ReturnType<typeof fsMock.readdir>>,
    );
    readFile.mockResolvedValueOnce(SKILL_WITH_FRONTMATTER);

    await run(["polymarket"]);

    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: {
        name: string;
        description: string;
        domain: string;
        version: string;
        requires: string[];
        tools: string[];
        content: string;
      };
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data.name).toBe("polymarket");
    expect(parsed.data.domain).toBe("platform");
    expect(parsed.data.version).toBe("1.0.0");
    expect(parsed.data.requires).toEqual(["prediction-markets"]);
    expect(parsed.data.tools).toEqual(["canon-cli"]);
    expect(parsed.data.content).toContain(
      "Polymarket Platform Knowledge",
    );
  });

  it("shows content for skill without frontmatter", async () => {
    readdir.mockResolvedValueOnce(
      ["orchestrator.md"] as unknown as
        Awaited<ReturnType<typeof fsMock.readdir>>,
    );
    readFile.mockResolvedValueOnce(SKILL_NO_FRONTMATTER);

    await run(["orchestrator"]);

    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: {
        name: string;
        content: string;
      };
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data.name).toBe("orchestrator");
    expect(parsed.data.content).toContain("Orchestrator Skill");
  });

  it("returns error for unknown topic", async () => {
    readdir.mockResolvedValueOnce(
      ["polymarket.md"] as unknown as
        Awaited<ReturnType<typeof fsMock.readdir>>,
    );
    readFile.mockResolvedValueOnce(SKILL_WITH_FRONTMATTER);

    await run(["nonexistent"]);

    const parsed = JSON.parse(stderrData) as {
      ok: boolean;
      error: string;
    };
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toContain('Unknown topic "nonexistent"');
    expect(parsed.error).toContain("polymarket");
  });

  it("supports --pretty flag for topic detail", async () => {
    readdir.mockResolvedValueOnce(
      ["polymarket.md"] as unknown as
        Awaited<ReturnType<typeof fsMock.readdir>>,
    );
    readFile.mockResolvedValueOnce(SKILL_WITH_FRONTMATTER);

    await run(["polymarket", "--pretty"]);

    expect(stdoutData).toContain("\n");
    const parsed = JSON.parse(stdoutData) as {
      ok: boolean;
      data: { name: string };
    };
    expect(parsed.ok).toBe(true);
    expect(parsed.data.name).toBe("polymarket");
  });
});
