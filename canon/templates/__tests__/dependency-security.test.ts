import { createRequire } from "node:module";
import { describe, expect, it } from "vitest";

const require = createRequire(import.meta.url);
const pmxtRequire = createRequire(require.resolve("pmxt-core"));
const expressRequire = createRequire(pmxtRequire.resolve("express"));
const proxyAddress = expressRequire("proxy-addr") as {
  compile: (subnet: string) => (address: string) => boolean;
};
const { Connection } = pmxtRequire("@solana/web3.js") as {
  Connection: new (url: string, config: { fetch: typeof fetch }) => {
    getSlot: () => Promise<number>;
  };
};

describe("security dependency compatibility", () => {
  it.each(["::ffff:10.0.0.0/8", "::/1"])(
    "does not trust arbitrary IPv4 clients for ambiguous subnet %s",
    (subnet) => expect(proxyAddress.compile(subnet)("203.0.113.1")).toBe(false),
  );

  it("preserves correctly configured IPv4 proxy trust", () => {
    const trust = proxyAddress.compile("10.0.0.0/8");
    expect(trust("10.1.2.3")).toBe(true);
    expect(trust("203.0.113.1")).toBe(false);
  });

  it("preserves Solana JSON-RPC responses with the updated browser client", async () => {
    const connection = new Connection("http://127.0.0.1:8899", {
      fetch: async (_url, init) => {
        const request = JSON.parse(String(init?.body)) as { method: string; id: string };
        expect(request.method).toBe("getSlot");
        return new Response(JSON.stringify({ jsonrpc: "2.0", id: request.id, result: 42 }));
      },
    });
    await expect(connection.getSlot()).resolves.toBe(42);
  });

  it("propagates JSON-RPC errors through the updated browser client", async () => {
    const connection = new Connection("http://127.0.0.1:8899", {
      fetch: async (_url, init) => {
        const request = JSON.parse(String(init?.body)) as { id: string };
        return new Response(JSON.stringify({
          jsonrpc: "2.0", id: request.id,
          error: { code: -32600, message: "security test rejection" },
        }));
      },
    });
    await expect(connection.getSlot()).rejects.toThrow("security test rejection");
  });
});
