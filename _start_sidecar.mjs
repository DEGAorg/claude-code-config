import { Polymarket } from "pmxtjs";
const poly = new Polymarket({ autoStartServer: true });
// Just a method known to work, kicks the autostart
await poly.fetchOrderBook("92156510891798873020497715268024772851858076229893943637545856397683791106647");
console.log("sidecar up");
process.exit(0);
