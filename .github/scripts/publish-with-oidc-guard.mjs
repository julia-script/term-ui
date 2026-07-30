#!/usr/bin/env node
/**
 * Runs the real publish and fails the release if OIDC was skipped.
 *
 * pnpm downgrades a failed OIDC exchange to a warning — `Skipped OIDC: <reason>`
 * — and then publishes with whatever other credential it can find. A green
 * workflow is therefore NOT evidence of a trusted release. This wrapper watches
 * for that warning and turns it into a failure.
 *
 * CRITICAL: stdout must be forwarded byte-for-byte. `changesets/action` parses
 * the publish output to produce its `published` and `publishedPackages`
 * outputs; swallowing or reformatting stdout silently disables the downstream
 * trust check and stops tags from being pushed. The test alongside this file
 * asserts that property.
 */
import { spawn } from "node:child_process";

const SKIPPED_OIDC = "Skipped OIDC";

/**
 * @param {string} command
 * @param {string[]} args
 * @param {{stdout: NodeJS.WritableStream, stderr: NodeJS.WritableStream, spawnFn?: typeof spawn}} io
 * @returns {Promise<{code: number, sawSkippedOidc: boolean}>}
 */
export function runGuardedPublish(
  command,
  args,
  io,
) {
  const spawnFn = io.spawnFn ?? spawn;
  return new Promise((resolve, reject) => {
    const child = spawnFn(command, args, {
      stdio: ["inherit", "pipe", "pipe"],
    });

    let sawSkippedOidc = false;

    // Watch both streams: pnpm's globalWarn goes to stderr, but keep stdout
    // covered too so a change in stream choice can't silently defeat the guard.
    const watch = (source, sink) => {
      source.on("data", (chunk) => {
        if (
          chunk.toString().includes(SKIPPED_OIDC)
        ) {
          sawSkippedOidc = true;
        }
        // pass the bytes through untouched — see the note above
        sink.write(chunk);
      });
    };

    watch(child.stdout, io.stdout);
    watch(child.stderr, io.stderr);

    child.on("error", reject);
    child.on("close", (code) => {
      resolve({
        code: code ?? 0,
        sawSkippedOidc,
      });
    });
  });
}

/* c8 ignore start -- entrypoint, exercised by the workflow rather than tests */
const isMain =
  process.argv[1] &&
  import.meta.url === `file://${process.argv[1]}`;

if (isMain) {
  const args = process.argv.slice(2);
  const [command, ...rest] =
    args.length > 0
      ? args
      : ["pnpm", "run", "publish"];

  const { code, sawSkippedOidc } =
    await runGuardedPublish(command, rest, {
      stdout: process.stdout,
      stderr: process.stderr,
    });

  if (sawSkippedOidc) {
    process.stderr.write(
      "\n::error::OIDC was skipped — this release would not be trusted. " +
        "Check that the npm trusted publisher names this exact workflow " +
        "filename, and that id-token: write is granted.\n",
    );
    process.exit(1);
  }

  process.exit(code);
}
/* c8 ignore stop */
