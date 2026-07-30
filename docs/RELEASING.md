# Releasing

Releases publish from GitHub Actions using npm **trusted publishing** (OIDC).
There is no `NPM_TOKEN` — the workflow authenticates with a short-lived
credential minted by Actions for that specific run.

## The flow

```
  PR containing a changeset is merged
        │
        ▼
  .github/workflows/release.yml
        │
        ├── changesets pending? ──▶ opens/updates the "Version Packages" PR
        │                            (publishes nothing)
        │
        └── none pending?       ──▶ build → tests → clean-room check
                                    → publish (OIDC-guarded)
                                    → verify trust on the registry
```

Day to day: add a changeset with `pnpm changeset`, merge your PR, then merge
the Version Packages PR that appears. That second merge is what publishes.

All four published packages are a changesets **`fixed` group**, so they always
share a version number and release together.

## Four things that will bite you

### 1. The publishing tool must stay pnpm

`changeset publish` picks its tool from the root `packageManager` field. Every
published package depends on siblings via `workspace:*`, and only `pnpm publish`
rewrites those into real version ranges on the way out. If `npm publish` ran
instead, `workspace:*` would reach the registry and the package would install
but fail to resolve.

### 2. pnpm must stay on 11.x

**The entire pnpm 10.x line has no OIDC support** — verified by grepping the
`npm/v1/oidc` token-exchange path across every cached release: absent in 9.x and
all of 10.x, present from 11.10.0 on. `packageManager` is pinned to `11.15.1`
and the workflow pins the same. Treat a pnpm bump as a change to the release
path, not a routine dependency update.

### 3. A failed OIDC exchange does not fail the publish

This is the dangerous one. pnpm downgrades both failure modes — no Actions
identity token, and a rejected exchange — to a warning:

```
WARN  Skipped OIDC: <reason>
```

…and then publishes with any other credential it can find. **A green workflow is
not evidence of a trusted release.** Two independent guards cover this:

| Guard | When | What it catches |
|---|---|---|
| [`publish-with-oidc-guard.mjs`](../.github/scripts/publish-with-oidc-guard.mjs) | during publish | watches the publish output for `Skipped OIDC` and fails the release |
| [`verify-release-trust.mjs`](../.github/scripts/verify-release-trust.mjs) | after publish | reads each package's registry packument and requires `_npmUser.trustedPublisher`, `dist.attestations.provenance`, no surviving `workspace:` range, and one aligned version across the fixed group |

Neither covers the other's case, so both stay. The during-publish guard forwards
stdout **byte-for-byte** — `changesets/action` parses that output to produce its
`published` and `publishedPackages` outputs, so swallowing it would silently
disable the second guard and stop tags being pushed. A test asserts that.

The verifier reads the packument over HTTP rather than using `npm view`, which
renders `_npmUser` as a display string and hides `trustedPublisher` entirely.

Both scripts are covered by `.github/scripts/release-guards.test.mjs`, which
runs as part of `pnpm test`.

### 4. The publish command must be `changeset publish`

`changesets/action@v1` sets its `published` and `publishedPackages` outputs by
scanning publish stdout for **`New tag: <pkg>@<version>`** — a line the
changesets CLI prints and `pnpm publish` does not. Calling `pnpm publish`
directly still publishes correctly, but the action sees zero released packages,
so **git tags and GitHub releases are never created and the post-publish
verifier is skipped** (it is gated on `published == 'true'`).

So the chain is: action → OIDC guard → `pnpm run publish` → `changeset publish`
→ `pnpm publish`. The CLI resolves its publishing tool from `packageManager`,
which keeps rule 1 satisfied.

### Bonus: the workflow filename is load-bearing

npm matches the trusted publisher's *workflow filename* field against the OIDC
token's `job_workflow_ref` claim. A mismatch produces the silent fallback above,
not a clear error. This repo is configured as **`release.yml`**. Renaming the
file means updating the npm config for all four packages first.

## npm configuration (website only)

For each of `@term-ui/core`, `@term-ui/dom`, `@term-ui/react`, `@term-ui/shared`,
at `https://www.npmjs.com/package/<name>/access`:

| Field | Value |
|---|---|
| Organization or user | `julia-script` |
| Repository | `term-ui` |
| Workflow filename | `release.yml` |
| Environment | *(blank)* |

Once the first OIDC release succeeds, set **Publishing access** to
*"Require two-factor authentication and disallow tokens"*. That is what makes
the silent-fallback hazard impossible rather than merely detected.

There must be **no `NPM_TOKEN`** in repository, organization, or Dependabot
secrets. Its absence is what turns a misconfiguration into a clean failure
instead of an untrusted publish.

## After the first release

Verify on the registry, not in the workflow log:

```sh
npm audit signatures   # in a clean dir, after installing the family
```

Expect *"N packages have verified attestations"*. The workflow log should
contain:

```
No NPM_TOKEN found, but OIDC is available - using npm trusted publishing
```

If you see `Skipped OIDC` instead, the release was not trusted. **Do not retry
the same version** — a published version cannot be replaced. Fix the
configuration and release the next one.

## What cannot be tested locally

The OIDC exchange needs an Actions-issued identity token, so `--dry-run` does
not exercise it and no local run can prove it works. What *is* verified locally:
the check gate passes, the workflow parses, the guard forwards stdout unchanged,
and no `NPM_TOKEN` exists. **The first real publish is the first true test of
OIDC** — which is exactly what the two guards exist to make safe.
