import { Wallet } from "ethers";
import { writeFileSync, existsSync } from "node:fs";

const envPath = new URL("../.env", import.meta.url).pathname;
if (existsSync(envPath)) {
  console.error(`refusing to overwrite existing ${envPath}`);
  process.exit(1);
}

const w = Wallet.createRandom();
writeFileSync(
  envPath,
  `POLYMARKET_PRIVATE_KEY=${w.privateKey}\n`,
  { mode: 0o600 },
);
console.log("address:", w.address);
console.log("saved key to:", envPath);
