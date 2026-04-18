import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type {
  MarketPrice,
  OrderBook,
  PolymarketMatch,
  PriceCandle,
} from "canon-templates/client-polymarket.js";

vi.mock("canon-templates/client-polymarket.js", () => ({
  searchMarkets: vi.fn(),
  fetchMarketPrice: vi.fn(),
  fetchOrderBook: vi.fn(),
  fetchOHLCV: vi.fn(),
}));

// Import after mock setup so the module gets the mocked version.
const {
  searchMarkets,
  fetchMarketPrice,
  fetchOrderBook,
  fetchOHLCV,
} = await import("canon-templates/client-polymarket.js");

const mockedSearch = vi.mocked(searchMarkets);
const mockedPrice = vi.mocked(fetchMarketPrice);
const mockedOrderBook = vi.mocked(fetchOrderBook);
const mockedOHLCV = vi.mocked(fetchOHLCV);

/** Capture stdout/stderr writes during a run() call. */
async function captureOutput(
  fn: () => Promise<void>,
): Promise<{ stdout: string; stderr: string; exitCode: number | undefined }> {
  let stdout = "";
  let stderr = "";
  const origOut = process.stdout.write.bind(process.stdout);
  const origErr = process.stderr.write.bind(process.stderr);
  const origExitCode = process.exitCode;

  process.stdout.write = ((chunk: string) => {
    stdout += chunk;
    return true;
  }) as typeof process.stdout.write;

  process.stderr.write = ((chunk: string) => {
    stderr += chunk;
    return true;
  }) as typeof process.stderr.write;

  process.exitCode = undefined;

  try {
    await fn();
    return { stdout, stderr, exitCode: process.exitCode };
  } finally {
    process.stdout.write = origOut;
    process.stderr.write = origErr;
    process.exitCode = origExitCode;
  }
}

describe("market subcommand", () => {
  let run: (args: string[]) => Promise<void>;

  beforeEach(async () => {
    vi.clearAllMocks();
    const mod = await import("../commands/market.js");
    run = mod.run;
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe("routing", () => {
    it("errors on unknown subcommand", async () => {
      const { stderr, exitCode } = await captureOutput(() =>
        run(["unknown"]),
      );
      const parsed = JSON.parse(stderr.trim()) as { ok: boolean; error: string };
      expect(parsed.ok).toBe(false);
      expect(parsed.error).toContain("Unknown market subcommand");
      expect(exitCode).toBe(1);
    });

    it("errors on missing subcommand", async () => {
      const { stderr, exitCode } = await captureOutput(() => run([]));
      const parsed = JSON.parse(stderr.trim()) as { ok: boolean; error: string };
      expect(parsed.ok).toBe(false);
      expect(parsed.error).toContain("Unknown market subcommand");
      expect(exitCode).toBe(1);
    });
  });

  describe("search", () => {
    const mockResults: PolymarketMatch[] = [
      {
        conditionId: "0xabc",
        question: "Will Bitcoin hit $100k?",
        yesPrice: 0.65,
        noPrice: 0.35,
        yesTokenId: "yes-token-abc",
        noTokenId: "no-token-abc",
        resolutionDate: "2026-12-31T00:00:00.000Z",
      },
    ];

    it("returns JSON with matching markets", async () => {
      mockedSearch.mockResolvedValueOnce(mockResults);

      const { stdout } = await captureOutput(() =>
        run(["search", "bitcoin"]),
      );
      const parsed = JSON.parse(stdout.trim()) as {
        ok: boolean;
        data: PolymarketMatch[];
      };
      expect(parsed.ok).toBe(true);
      expect(parsed.data).toEqual(mockResults);
      expect(mockedSearch).toHaveBeenCalledWith("bitcoin");
    });

    it("joins multi-word queries", async () => {
      mockedSearch.mockResolvedValueOnce([]);

      await captureOutput(() =>
        run(["search", "will", "bitcoin", "hit", "100k"]),
      );
      expect(mockedSearch).toHaveBeenCalledWith(
        "will bitcoin hit 100k",
      );
    });

    it("errors on missing query", async () => {
      const { stderr, exitCode } = await captureOutput(() =>
        run(["search"]),
      );
      const parsed = JSON.parse(stderr.trim()) as { ok: boolean; error: string };
      expect(parsed.ok).toBe(false);
      expect(parsed.error).toContain("Missing search query");
      expect(exitCode).toBe(1);
    });

    it("handles API errors", async () => {
      mockedSearch.mockRejectedValueOnce(new Error("Network timeout"));

      const { stderr, exitCode } = await captureOutput(() =>
        run(["search", "bitcoin"]),
      );
      const parsed = JSON.parse(stderr.trim()) as { ok: boolean; error: string };
      expect(parsed.ok).toBe(false);
      expect(parsed.error).toBe("Network timeout");
      expect(exitCode).toBe(1);
    });

    it("strips --pretty from query args", async () => {
      mockedSearch.mockResolvedValueOnce(mockResults);

      const { stdout } = await captureOutput(() =>
        run(["search", "--pretty", "bitcoin"]),
      );
      expect(mockedSearch).toHaveBeenCalledWith("bitcoin");
      expect(stdout).toContain("\n ");
    });
  });

  describe("price", () => {
    const mockPrice: MarketPrice = {
      conditionId: "0xabc",
      yes: 0.65,
      no: 0.35,
      timestamp: new Date("2026-04-14T12:00:00Z"),
    };

    it("returns price for a condition ID", async () => {
      mockedPrice.mockResolvedValueOnce(mockPrice);

      const { stdout } = await captureOutput(() =>
        run(["price", "0xabc"]),
      );
      const parsed = JSON.parse(stdout.trim()) as {
        ok: boolean;
        data: MarketPrice;
      };
      expect(parsed.ok).toBe(true);
      expect(parsed.data.conditionId).toBe("0xabc");
      expect(parsed.data.yes).toBe(0.65);
      expect(mockedPrice).toHaveBeenCalledWith("0xabc");
    });

    it("errors on missing condition ID", async () => {
      const { stderr, exitCode } = await captureOutput(() =>
        run(["price"]),
      );
      const parsed = JSON.parse(stderr.trim()) as { ok: boolean; error: string };
      expect(parsed.ok).toBe(false);
      expect(parsed.error).toContain("Missing condition ID");
      expect(exitCode).toBe(1);
    });

    it("handles market not found", async () => {
      mockedPrice.mockRejectedValueOnce(
        new Error("Market 0xdead not found"),
      );

      const { stderr, exitCode } = await captureOutput(() =>
        run(["price", "0xdead"]),
      );
      const parsed = JSON.parse(stderr.trim()) as { ok: boolean; error: string };
      expect(parsed.ok).toBe(false);
      expect(parsed.error).toBe("Market 0xdead not found");
      expect(exitCode).toBe(1);
    });
  });

  describe("orderbook", () => {
    const mockBook: OrderBook = {
      tokenId: "tok-123",
      bids: [
        { price: 0.6, size: 100 },
        { price: 0.55, size: 200 },
      ],
      asks: [
        { price: 0.65, size: 150 },
        { price: 0.7, size: 300 },
      ],
    };

    it("returns orderbook for a token ID", async () => {
      mockedOrderBook.mockResolvedValueOnce(mockBook);

      const { stdout } = await captureOutput(() =>
        run(["orderbook", "tok-123"]),
      );
      const parsed = JSON.parse(stdout.trim()) as {
        ok: boolean;
        data: OrderBook;
      };
      expect(parsed.ok).toBe(true);
      expect(parsed.data.tokenId).toBe("tok-123");
      expect(parsed.data.bids).toHaveLength(2);
      expect(parsed.data.asks).toHaveLength(2);
      expect(mockedOrderBook).toHaveBeenCalledWith("tok-123");
    });

    it("errors on missing token ID", async () => {
      const { stderr, exitCode } = await captureOutput(() =>
        run(["orderbook"]),
      );
      const parsed = JSON.parse(stderr.trim()) as { ok: boolean; error: string };
      expect(parsed.ok).toBe(false);
      expect(parsed.error).toContain("Missing token ID");
      expect(exitCode).toBe(1);
    });

    it("handles API errors", async () => {
      mockedOrderBook.mockRejectedValueOnce(
        new Error("Token not found"),
      );

      const { stderr, exitCode } = await captureOutput(() =>
        run(["orderbook", "bad-token"]),
      );
      const parsed = JSON.parse(stderr.trim()) as { ok: boolean; error: string };
      expect(parsed.ok).toBe(false);
      expect(parsed.error).toBe("Token not found");
      expect(exitCode).toBe(1);
    });
  });

  describe("ohlcv", () => {
    const mockCandles: PriceCandle[] = [
      {
        timestamp: 1713100800000,
        open: 0.6,
        high: 0.68,
        low: 0.58,
        close: 0.65,
        volume: 5000,
      },
      {
        timestamp: 1713104400000,
        open: 0.65,
        high: 0.7,
        low: 0.63,
        close: 0.67,
        volume: null,
      },
    ];

    it("returns OHLCV candles for a token ID", async () => {
      mockedOHLCV.mockResolvedValueOnce(mockCandles);

      const { stdout } = await captureOutput(() =>
        run(["ohlcv", "tok-456"]),
      );
      const parsed = JSON.parse(stdout.trim()) as {
        ok: boolean;
        data: PriceCandle[];
      };
      expect(parsed.ok).toBe(true);
      expect(parsed.data).toHaveLength(2);
      expect(parsed.data[0]?.close).toBe(0.65);
      expect(mockedOHLCV).toHaveBeenCalledWith("tok-456", undefined);
    });

    it("passes --timeframe option", async () => {
      mockedOHLCV.mockResolvedValueOnce(mockCandles);

      await captureOutput(() =>
        run(["ohlcv", "tok-456", "--timeframe", "5m"]),
      );
      expect(mockedOHLCV).toHaveBeenCalledWith("tok-456", {
        timeframe: "5m",
      });
    });

    it("errors on missing token ID", async () => {
      const { stderr, exitCode } = await captureOutput(() =>
        run(["ohlcv"]),
      );
      const parsed = JSON.parse(stderr.trim()) as { ok: boolean; error: string };
      expect(parsed.ok).toBe(false);
      expect(parsed.error).toContain("Missing token ID");
      expect(exitCode).toBe(1);
    });

    it("handles sidecar errors", async () => {
      mockedOHLCV.mockRejectedValueOnce(
        new Error("Sidecar not running"),
      );

      const { stderr, exitCode } = await captureOutput(() =>
        run(["ohlcv", "tok-456"]),
      );
      const parsed = JSON.parse(stderr.trim()) as { ok: boolean; error: string };
      expect(parsed.ok).toBe(false);
      expect(parsed.error).toBe("Sidecar not running");
      expect(exitCode).toBe(1);
    });

    it("strips --pretty but keeps --timeframe", async () => {
      mockedOHLCV.mockResolvedValueOnce(mockCandles);

      const { stdout } = await captureOutput(() =>
        run(["ohlcv", "tok-456", "--pretty", "--timeframe", "1d"]),
      );
      expect(mockedOHLCV).toHaveBeenCalledWith("tok-456", {
        timeframe: "1d",
      });
      expect(stdout).toContain("\n ");
    });
  });
});
