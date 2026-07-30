# Design: Release Prep

## JSX element typing

### History

The elements were originally named `term-view`/`term-text` precisely because `view` and `text` could not be reclaimed: `@types/react` declares both as SVG intrinsics (`SVGViewElement`, `SVGTextElement`), a global `IntrinsicElements` augmentation can only *add* keys, and re-declaring an existing key is a duplicate-property error. The custom names were the workaround. The elements were later renamed to `view`/`text` (better ergonomics), which silently reintroduced the original problem — hence today's `as object` casts for `contentEditable`, and event handlers typed as SVG mouse events.

### What changed

`jsxImportSource` (TypeScript 4.1+) resolves `JSX.IntrinsicElements` from a *module-scoped* namespace instead of the global one, so it replaces React's table rather than merging with it. This was verified against this repo (TypeScript 5.8, `@types/react` 19.2 present and resolving):

- `<view contentEditable onClick={e => …}>` type-checks with **no cast**, and the handler parameter is our event type, not `MouseEvent<SVGViewElement>`.
- An unknown prop is a type error (`Property 'bogusProp' does not exist`), so the table is genuinely ours and not a permissive `any`.
- Removing `jsxImportSource` reproduces the old `SVGProps<SVGViewElement>` failure exactly — confirming the mechanism, not a coincidence.

So the constraint that forced `term-view` is real but no longer binding. We keep `view`/`text` and fix the typing properly.

### Shape

A `@term-ui/react/jsx-runtime` entry (plus `jsx-dev-runtime`) that re-exports React's runtime unchanged and declares the element table:

```ts
export { Fragment, jsx, jsxs } from "react/jsx-runtime";
export namespace JSX {
  interface IntrinsicElements { view: TermViewProps; text: TermTextProps }
  // Element / ElementChildrenAttribute must be declared too — the namespace
  // replaces React's wholesale, it does not inherit from it
}
```

Consumers set `"jsxImportSource": "@term-ui/react"`. This is the same pattern Preact and Emotion use, so it is a familiar one-line tsconfig change rather than a novel requirement.

**Prop types must be complete before this lands.** Because the namespace replaces React's entirely, anything omitted becomes a hard error rather than falling back: `key`, `ref`, `children`, and every event prop the reconciler maps (`onClick`, `onMouseEnter/Leave/Move/Down/Up`, `onScroll`) must be present. A probe with a deliberately minimal prop type produced exactly these errors in our own test file, which is a useful checklist.

**Runtime is unaffected** — the runtime re-export is React's own, so this is purely a type-level change. Existing `TermViewProps`/`TermTextProps` in `src/types.ts` are the starting point; the dead `term-view`/`term-text` global augmentation in `src/index.ts` is removed.

**Fallback if the entry point proves awkward for a consumer**: they can keep `jsx: "react-jsx"` without `jsxImportSource` and cast, exactly as today. Nothing regresses; the typing is an improvement layered on top.

## Dependency triage

Determined by grepping shipped source for each declared dependency:

| Package | Move out of `dependencies` | Why |
|---|---|---|
| `dom` | `@trpc/client`, `socket.io-client`, `@types/ws` | imported nowhere at all |
| `dom` | `@trpc/server`, `ws`, `zod` | imported only by `src/devtools`, which is not in the published export surface |
| `core` | `chrome-remote-interface`, `ts-dedent` | not imported by shipped JS |
| `react` | `@types/node` | types-only |
| `core` | `@types/node`, `@types/lodash-es` | types-only |

`lodash-es` and `valibot` (core), `lodash-es` and `react-reconciler` (react) stay — they are genuinely imported.

**Devtools removed outright** (revised during implementation). Dropping only the `./devtools` export was not sufficient: `Document.ts` imported `devtools` at module top level and invoked it under a `dev` option, so tRPC/ws/zod were runtime dependencies of the *main* export, and excluding the folder from the build broke `Document`. Devtools is therefore deleted from `dom` along with the `dev` option; `packages/devtools` (the UI half, which imported `@term-ui/dom/devtools`) is private and excluded from the build pipeline. The experiment can return as a self-contained package.

**Also found during implementation**: `@term-ui/core` and `@term-ui/shared` were `devDependencies` of `dom` and `react` despite being imported for *values* at runtime (`HitTestFilter`, `raise`, `loader`) — a clean install of either package would have failed. They are now real dependencies. `@types/node` had been reaching `dom` transitively through the removed devtools deps; `dom` genuinely needs it (`process`, `node:util`, `Symbol.dispose`), so it is now an explicit devDependency. `packages/cssom` turned out to be an empty directory containing only a stale zig cache, and was deleted.

## Versioning

Publish at `0.1.0`. Registry currently has core 0.0.0 / dom 0.0.1 / react 0.0.1; the repo's 0.0.1/0.0.2/0.0.2 were bumped but never published, so continuing the 0.0.x line would ship "patches" over an engine that was rebuilt. `0.1.0` signals the reset honestly while staying pre-1.0. All published packages move together (changesets `fixed` group) so version numbers stop drifting apart.

The stale `.changeset/wet-breads-win.md` ("Implement separate String entity") describes work already in the tree from before the revival; it is removed rather than shipped as a changelog entry.

## Verification: clean-room install

The one check that actually proves distribution works, and the only way to catch a missing file or a bad `exports` map:

1. `pnpm build` (all packages, including the wasm artifacts)
2. `npm pack` each published package → tarballs
3. install the tarballs into a scratch project outside the repo
4. run a quickstart program copied verbatim from the README, under a pty
5. assert it renders expected output and exits cleanly

This runs as a script so it can be repeated before any future publish. It also validates the README, since the program is copied from it rather than written for the test.

## Out of scope

Merging `block-layout` → `main` and running `pnpm publish`. Both are maintainer decisions; this change makes them safe to perform, and the clean-room script is the gate.
