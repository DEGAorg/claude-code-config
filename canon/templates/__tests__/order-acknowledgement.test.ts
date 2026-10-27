import { createRequire } from "node:module";
import { expect, it, vi } from "vitest";

type OrderResponse = {
  success: boolean;
  orderID: string;
  tradeIDs: string[];
  transactionsHashes: string[];
};
type OfflineClient = {
  post: () => Promise<OrderResponse>;
  getTrades: () => Promise<unknown[]>;
  postOrder: (order: { salt: string }) => Promise<OrderResponse>;
};
const require = createRequire(import.meta.url);
const pmxtRequire = createRequire(require.resolve("pmxt-core"));
const { ClobClient } = pmxtRequire("@polymarket/clob-client-v2") as {
  ClobClient: new (config: {
    host: string;
    chain: number;
    signer: { getAddress: () => Promise<string>; _signTypedData: () => never };
    creds: { key: string; secret: string; passphrase: string };
  }) => OfflineClient;
};

it("acknowledges an accepted order before its transaction settles", async () => {
  vi.useFakeTimers();
  try {
    const response: OrderResponse = {
      success: true, orderID: "fixture-order", tradeIDs: ["fixture-trade"],
      transactionsHashes: [],
    };
    const client = new ClobClient({
      host: "https://offline.invalid", chain: 137,
      signer: {
        getAddress: async () => "0x0000000000000000000000000000000000000001",
        _signTypedData: () => { throw new Error("Unexpected signing in offline test"); },
      },
      creds: { key: "fixture", secret: "dGVzdA==", passphrase: "fixture" },
    });
    client.post = vi.fn(async () => response);
    client.getTrades = vi.fn(async () => []);
    let acknowledged = false;
    const pending = client.postOrder({ salt: "1" }).then((result) => {
      acknowledged = result.orderID === response.orderID;
    });
    await vi.waitFor(() => expect(client.post).toHaveBeenCalledTimes(1));
    await vi.advanceTimersByTimeAsync(0);
    const acknowledgedWithoutWaiting = acknowledged;
    await vi.advanceTimersByTimeAsync(30_000);
    await pending;
    expect(acknowledgedWithoutWaiting).toBe(true);
  } finally {
    vi.useRealTimers();
  }
});
