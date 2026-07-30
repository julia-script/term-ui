#!/usr/bin/env node
/**
 * Confirms on the registry that a release was actually trusted.
 *
 * The during-publish guard catches a skipped OIDC exchange. This catches
 * everything else: it reads what the registry actually stored and fails unless
 * every published package has trusted-publisher provenance and clean metadata.
 *
 * Reads the packument over HTTP rather than using `npm view`, which renders
 * `_npmUser` as a display string and hides `trustedPublisher` entirely.
 */
const REGISTRY = "https://registry.npmjs.org";

/** A freshly published version can lag in the packument. */
const RETRIES = 6;
const RETRY_DELAY_MS = 5000;

const sleep = (ms) =>
  new Promise((r) => setTimeout(r, ms));

/**
 * @param {string} name
 * @param {{fetchFn?: typeof fetch}} [io]
 */
export async function fetchPackument(
  name,
  io = {},
) {
  const fetchFn = io.fetchFn ?? fetch;
  const response = await fetchFn(
    `${REGISTRY}/${name.replace("/", "%2f")}`,
    { headers: { accept: "application/json" } },
  );
  if (!response.ok) {
    throw new Error(
      `registry returned ${response.status} for ${name}`,
    );
  }
  return response.json();
}

/**
 * Check one published version. Returns a list of problems (empty === good).
 *
 * @param {object} versionDoc the packument's entry for the released version
 * @returns {string[]}
 */
export function checkVersion(versionDoc) {
  const problems = [];

  if (!versionDoc?._npmUser?.trustedPublisher) {
    problems.push(
      "no _npmUser.trustedPublisher — the release was not published via OIDC",
    );
  }
  if (
    !versionDoc?.dist?.attestations?.provenance
  ) {
    problems.push(
      "no dist.attestations.provenance",
    );
  }

  // a `workspace:` range that survived into the registry installs but cannot
  // resolve for consumers
  for (const field of [
    "dependencies",
    "peerDependencies",
  ]) {
    for (const [dep, range] of Object.entries(
      versionDoc?.[field] ?? {},
    )) {
      if (
        String(range).startsWith("workspace:")
      ) {
        problems.push(
          `${field}.${dep} published as "${range}" — pnpm did not rewrite it`,
        );
      }
    }
  }

  return problems;
}

/**
 * @param {Array<{name: string, version: string}>} released
 * @param {{expectAlignedVersions?: boolean}} [options]
 * @returns {string[]} problems
 */
export function checkReleaseSet(
  released,
  options = {},
) {
  const problems = [];
  if (released.length === 0) {
    problems.push(
      "no packages were reported as published",
    );
  }
  // Only meaningful with a changesets `fixed`/`linked` group; independent
  // versions would fail this spuriously.
  if (
    options.expectAlignedVersions &&
    released.length > 1
  ) {
    const versions = new Set(
      released.map((p) => p.version),
    );
    if (versions.size > 1) {
      problems.push(
        `versions are not aligned across the fixed group: ${[...versions].join(", ")}`,
      );
    }
  }
  return problems;
}

/* c8 ignore start -- entrypoint */
const isMain =
  process.argv[1] &&
  import.meta.url === `file://${process.argv[1]}`;

if (isMain) {
  // changesets/action publishes this as JSON: [{name, version}, ...]
  const raw =
    process.env.PUBLISHED_PACKAGES ?? "[]";
  /** @type {Array<{name: string, version: string}>} */
  let released;
  try {
    released = JSON.parse(raw);
  } catch {
    console.error(
      `could not parse PUBLISHED_PACKAGES: ${raw.slice(0, 200)}`,
    );
    process.exit(1);
  }

  const problems = checkReleaseSet(released, {
    expectAlignedVersions: true,
  });

  for (const { name, version } of released) {
    let versionDoc;
    for (
      let attempt = 1;
      attempt <= RETRIES;
      attempt++
    ) {
      const packument =
        await fetchPackument(name);
      versionDoc = packument.versions?.[version];
      if (versionDoc) break;
      if (attempt < RETRIES)
        await sleep(RETRY_DELAY_MS);
    }

    if (!versionDoc) {
      problems.push(
        `${name}@${version} never appeared in the registry packument`,
      );
      continue;
    }

    for (const problem of checkVersion(
      versionDoc,
    )) {
      problems.push(
        `${name}@${version}: ${problem}`,
      );
    }
  }

  if (problems.length > 0) {
    console.error(
      "Release trust verification FAILED:",
    );
    for (const p of problems)
      console.error(`  - ${p}`);
    console.error(
      "\nA published version cannot be replaced. Fix the configuration " +
        "and release the next version rather than retrying this one.",
    );
    process.exit(1);
  }

  console.log(
    `Verified ${released.length} package(s): trusted publisher + provenance present.`,
  );
}
/* c8 ignore stop */
