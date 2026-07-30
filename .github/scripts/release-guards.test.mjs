import { EventEmitter } from "node:events";
import { describe, expect, it } from "vitest";
import { runGuardedPublish } from "./publish-with-oidc-guard.mjs";
import {
  checkReleaseSet,
  checkVersion,
} from "./verify-release-trust.mjs";

/** Minimal stand-in for a spawned process. */
const fakeChild = ({
  stdoutChunks = [],
  stderrChunks = [],
  code = 0,
}) => {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  queueMicrotask(() => {
    for (const c of stdoutChunks)
      child.stdout.emit("data", Buffer.from(c));
    for (const c of stderrChunks)
      child.stderr.emit("data", Buffer.from(c));
    child.emit("close", code);
  });
  return child;
};

const collector = () => {
  const chunks = [];
  return {
    sink: {
      write: (c) => {
        chunks.push(c);
        return true;
      },
    },
    text: () =>
      chunks.map((c) => c.toString()).join(""),
    raw: () =>
      Buffer.concat(chunks.map(Buffer.from)),
  };
};

describe("publish OIDC guard", () => {
  it("forwards stdout byte-for-byte", async () => {
    // changesets/action parses this output to build its `published` and
    // `publishedPackages` outputs — any mutation breaks the release
    const out = collector();
    const err = collector();
    const payload = [
      "+ @term-ui/core@0.1.0\n",
      "+ @term-ui/dom@0.1.0\n",
      "🦋  info npm info ok\n",
    ];

    const { code, sawSkippedOidc } =
      await runGuardedPublish(
        "pnpm",
        ["publish"],
        {
          stdout: out.sink,
          stderr: err.sink,
          spawnFn: () =>
            fakeChild({ stdoutChunks: payload }),
        },
      );

    expect(code).toBe(0);
    expect(sawSkippedOidc).toBe(false);
    expect(out.raw()).toEqual(
      Buffer.from(payload.join("")),
    );
  });

  it("flags a skipped OIDC exchange on stderr", async () => {
    const out = collector();
    const err = collector();
    const { sawSkippedOidc } =
      await runGuardedPublish(
        "pnpm",
        ["publish"],
        {
          stdout: out.sink,
          stderr: err.sink,
          spawnFn: () =>
            fakeChild({
              stdoutChunks: [
                "+ @term-ui/core@0.1.0\n",
              ],
              stderrChunks: [
                "WARN  Skipped OIDC: id token not available\n",
              ],
            }),
        },
      );

    expect(sawSkippedOidc).toBe(true);
    // and the warning still reaches the log
    expect(err.text()).toContain("Skipped OIDC");
  });

  it("flags it even if pnpm moves the warning to stdout", async () => {
    const out = collector();
    const err = collector();
    const { sawSkippedOidc } =
      await runGuardedPublish(
        "pnpm",
        ["publish"],
        {
          stdout: out.sink,
          stderr: err.sink,
          spawnFn: () =>
            fakeChild({
              stdoutChunks: [
                "WARN  Skipped OIDC: exchange rejected\n",
              ],
            }),
        },
      );
    expect(sawSkippedOidc).toBe(true);
  });

  it("propagates a non-zero exit code", async () => {
    const out = collector();
    const err = collector();
    const { code } = await runGuardedPublish(
      "pnpm",
      ["publish"],
      {
        stdout: out.sink,
        stderr: err.sink,
        spawnFn: () => fakeChild({ code: 1 }),
      },
    );
    expect(code).toBe(1);
  });
});

describe("release trust verification", () => {
  const trusted = {
    _npmUser: {
      name: "julia-script",
      trustedPublisher: {
        id: "github-actions",
        repository: "julia-script/term-ui",
      },
    },
    dist: {
      attestations: {
        provenance: { predicateType: "slsa" },
      },
    },
    dependencies: { "@term-ui/shared": "0.1.0" },
  };

  it("accepts a properly trusted version", () => {
    expect(checkVersion(trusted)).toEqual([]);
  });

  it("rejects a version with no trusted publisher", () => {
    const doc = {
      ...trusted,
      _npmUser: { name: "julia-script" },
    };
    expect(checkVersion(doc).join(" ")).toContain(
      "trustedPublisher",
    );
  });

  it("rejects a version with no provenance", () => {
    const doc = { ...trusted, dist: {} };
    expect(checkVersion(doc).join(" ")).toContain(
      "provenance",
    );
  });

  it("rejects a surviving workspace: range", () => {
    const doc = {
      ...trusted,
      dependencies: {
        "@term-ui/shared": "workspace:*",
      },
    };
    expect(checkVersion(doc).join(" ")).toContain(
      "workspace:",
    );
  });

  it("requires aligned versions across the fixed group", () => {
    const problems = checkReleaseSet(
      [
        {
          name: "@term-ui/core",
          version: "0.1.0",
        },
        {
          name: "@term-ui/dom",
          version: "0.1.1",
        },
      ],
      { expectAlignedVersions: true },
    );
    expect(problems.join(" ")).toContain(
      "not aligned",
    );
  });

  it("accepts aligned versions", () => {
    expect(
      checkReleaseSet(
        [
          {
            name: "@term-ui/core",
            version: "0.1.0",
          },
          {
            name: "@term-ui/dom",
            version: "0.1.0",
          },
        ],
        { expectAlignedVersions: true },
      ),
    ).toEqual([]);
  });

  it("fails when nothing was published", () => {
    expect(
      checkReleaseSet([], {
        expectAlignedVersions: true,
      }).join(" "),
    ).toContain("no packages");
  });
});
