# Tasks: Release Prep

## 1. JSX element typing

- [x] 1.1 Complete `TermViewProps`/`TermTextProps` in `packages/react/src/types.ts`: `key`, `ref`, `children`, and every event prop the reconciler maps (`onClick`, `onMouseEnter`, `onMouseLeave`, `onMouseMove`, `onMouseDown`, `onMouseUp`, `onScroll`), with our own event types
- [x] 1.2 Add `packages/react/jsx-runtime.{js,d.ts}` and `jsx-dev-runtime.{js,d.ts}` re-exporting React's runtime and declaring the `JSX` namespace (`IntrinsicElements`, `Element`, `ElementChildrenAttribute`)
- [x] 1.3 Wire `exports` for both entries; ensure they are in `files` so they publish
- [x] 1.4 Remove the dead `term-view`/`term-text` global augmentation from `packages/react/src/index.ts`
- [x] 1.5 Set `jsxImportSource` in the react package and all examples; delete every `as object` cast and `biome-ignore` for SVG-typed props
- [x] 1.6 Confirm a wrong prop is a type error and event handler params are our types (not SVG)

## 2. Dependencies and publish surface

- [x] 2.1 `dom`: remove `@trpc/client`, `socket.io-client`, `@types/ws`; move `@trpc/server`, `ws`, `zod` out of `dependencies`
- [x] 2.2 `dom`: remove devtools entirely — `Document` imported it at top level, so dropping only the export was not possible (see design note)
- [x] 2.3 `core`: remove `chrome-remote-interface`, `ts-dedent`; move `@types/*` to devDependencies
- [x] 2.4 `react`: move `@types/node` to devDependencies
- [x] 2.5 `packages/cssom` deleted (empty, only a stale zig cache); `packages/devtools` marked private and excluded from the build pipeline
- [x] 2.6 Verify each published package's `files`/`exports` covers exactly the built artifacts (core must include both wasm files)

## 3. Metadata and docs

- [x] 3.1 Corrected the existing LICENSE (copyright was a template leftover: "weth, LLC"), copied it into each published package, added `license: MIT` + `author` to every manifest
- [x] 3.2 Fix repository URLs (`dom` still says `yourusername`); add `repository.directory` to each
- [x] 3.3 Rewrite `packages/react/README.md` against the real API — `<view>`/`<text>`, `TermUi.createRoot`, the `jsxImportSource` line — replacing the `term-view`/`term-text` docs
- [x] 3.4 Write `packages/core/README.md` and `packages/shared/README.md` (both currently empty); review `packages/dom/README.md` for accuracy
- [x] 3.5 Refresh the root README Status section (the revival plan it describes is fully archived) and point at `openspec/specs/`

## 4. Release mechanics

- [x] 4.1 Delete the stale `.changeset/wet-breads-win.md`
- [x] 4.2 Group published packages as `fixed` in `.changeset/config.json` so versions stay aligned
- [x] 4.3 Added the release changeset and ran `changeset version` — all four published packages are at `0.1.0` (also upgraded changesets to 2.31.1 and rebuilt node_modules; the store had corrupt dependency nesting that broke the CLI)

## 5. Verification

- [ ] 5.1 Write a clean-room script: build → `npm pack` → install tarballs into a scratch project outside the repo → run the README quickstart under a pty → assert rendered output and clean exit
- [ ] 5.2 Run it; fix whatever it catches (missing files, bad exports, missing runtime deps)
- [ ] 5.3 Full suite green (`zig build test`, dom + react vitest) and every example still runs
