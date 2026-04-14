import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

const here = dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  resolve: {
    alias: {
      "canon-templates": resolve(here, "../templates"),
    },
  },
  test: {
    include: ["__tests__/**/*.test.ts"],
    exclude: ["node_modules/**", "dist/**"],
    passWithNoTests: true,
  },
});
