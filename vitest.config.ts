import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    workspace: [
      "packages/*",
      // Release guards live outside packages/ but must run in the normal
      // check command — they are what stands between a misconfiguration and
      // a silently untrusted publish.
      {
        test: {
          name: "release-scripts",
          include: [".github/scripts/*.test.mjs"],
        },
      },
    ],
  },
});
