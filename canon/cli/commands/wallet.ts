/**
 * Wallet subcommand — manage the project-local burner wallet.
 *
 * Usage:
 *   canon-cli wallet ensure   # generate if missing, idempotent
 *   canon-cli wallet address  # print the wallet address
 *   canon-cli wallet info     # address + wallet file path
 *
 * The wallet lives at `<cwd>/.canon/wallet.env` (mode 0600) so each
 * Canon project has its own burner. Different strategies in different
 * projects therefore use different accounts automatically.
 */

import { FileWalletStore } from "../wallet-store.js";
import { writeError, writeSuccess } from "../output.js";

const FUNDING_MESSAGE =
  "New burner wallet created. Fund this address with USDC.e on Polygon before running strategies.";
const EXISTING_MESSAGE = "Wallet already configured.";

type Sub = "ensure" | "address" | "info";

export async function run(args: string[]): Promise<void> {
  const sub = args[0] as Sub | undefined;
  const rest = args.slice(1);
  const store = new FileWalletStore();

  try {
    switch (sub) {
      case "ensure": {
        const result = await store.ensure();
        writeSuccess(
          {
            address: result.address,
            created: result.created,
            message: result.created ? FUNDING_MESSAGE : EXISTING_MESSAGE,
          },
          rest,
        );
        return;
      }
      case "address": {
        const address = await store.getAddress();
        writeSuccess({ address }, rest);
        return;
      }
      case "info": {
        const address = await store.getAddress();
        writeSuccess(
          { address, path: ".canon/wallet.env" },
          rest,
        );
        return;
      }
      default:
        writeError(
          `Unknown wallet subcommand "${sub ?? ""}". Expected: ensure | address | info.`,
          rest,
        );
        return;
    }
  } catch (err: unknown) {
    writeError(
      err instanceof Error ? err.message : String(err),
      rest,
    );
  }
}
