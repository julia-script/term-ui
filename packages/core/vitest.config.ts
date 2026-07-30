import { defineProject } from "vitest/config";

export default defineProject({
  test: {
    include: ["**/*.test.ts"],
    exclude: [
      "**/node_modules/**",
      "**/dist/**",
      "**/build/**",
      // Dead since the engine rebuild: these call wasm exports that no longer
      // exist (Tree_setElementId and friends). Coverage now lives in the Zig
      // suite and the dom/react vitest suites. Tracked for deletion/rewrite.
      "js/*.test.ts",
    ],
  },
});
