# Release Prep

## Why

The engine is stabilized and spec'd, but the packages are not shippable. Installing `@term-ui/dom` today pulls in tRPC, socket.io, ws and zod for a devtools experiment that isn't even reachable from its main export; `@term-ui/core` pulls `chrome-remote-interface`. The published `@term-ui/react` README documents a `<term-view>`/`<term-text>` element API that no longer exists, so anyone following it writes a broken app. There is no LICENSE file despite an MIT badge, no `license` field in any manifest, and one manifest still points at `github.com/yourusername/term-ui`. Meanwhile the JSX types for `view`/`text` resolve to React's SVG intrinsics, which is why our own examples need `as object` casts for `contentEditable`.

None of this is engine work — it is the difference between "I wouldn't trust this package" and one you would hand to someone.

## What Changes

- **Dependencies**: move every dependency not imported by shipped code out of `dependencies` (devtools-only tRPC/socket.io/ws/zod in `dom`, `chrome-remote-interface` and `ts-dedent` in `core`, `@types/node` in `react`). Type-only packages belong in `devDependencies`.
- **Publish surface**: mark the experiments (`cssom`, `devtools`) private so they cannot be published; fix the mis-scoped `@termui/devtools` name (missing hyphen) if it is kept at all; verify `files`/`exports` expose exactly the built artifacts and nothing else.
- **JSX element typing**: give `view`/`text` real types via a `jsx-runtime` entry point, so `contentEditable` and typed event handlers work without casts. **BREAKING** for consumers who set `jsxImportSource`; the examples move with it.
- **Metadata**: add a LICENSE file and a `license` field to every published manifest; correct repository URLs; ensure each published package has a non-empty README (`core` and `shared` are currently zero bytes).
- **Docs**: rewrite the `react` README against the real API (`<view>`/`<text>`, `TermUi.createRoot`) with a runnable example; refresh the root README's Status section, which still presents the (now fully archived) revival plan as the roadmap.
- Remove the stale `.changeset/wet-breads-win.md` describing already-shipped work; add changesets covering this release.
- **Version**: release the published packages as `0.1.0` rather than `0.0.x` — the engine differs substantially from what is on npm, and repo versions (`core` 0.0.1, `dom`/`react` 0.0.2) are already ahead of the registry (0.0.0/0.0.1/0.0.1) without ever being published.

Out of scope: merging `block-layout` into `main` and running the actual publish. Both remain manual decisions for the maintainer.

## Capabilities

### New Capabilities
- `package-distribution`: what the published packages must guarantee to a consumer — dependency honesty, a documented and type-correct public API surface, licensing and provenance metadata, and installability in a clean project.

### Modified Capabilities

None. Engine behavior is unchanged; this is the distribution boundary.

## Impact

- `packages/{core,dom,react,shared}/package.json` — dependencies, license, repository, files/exports.
- `packages/{cssom,devtools}/package.json` — marked private.
- `packages/react/src/index.ts`, new `packages/react/jsx-runtime` entry — element typing, replacing the dead `term-view`/`term-text` global augmentation.
- `examples/*` — adopt `jsxImportSource`, drop the `as object` casts.
- `packages/{core,dom,react,shared}/README.md`, root `README.md`, new `LICENSE`.
- `.changeset/` — remove stale entry, add release changesets.
- Verification: a packing smoke test (`npm pack` + install into a scratch project) proving a fresh consumer can render.
