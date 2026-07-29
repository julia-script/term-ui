# Cleanup Workspace

## Why

The project is being revived after ~6 months of hibernation. The working tree carries an abandoned experiment (Effect-based JS API), the branch tip is two commits literally named "tmp", and the repo contains 4+ directories that are not part of the product and were never wired into the workspace. Before any real work (Zig migration, test rebuild), the workspace needs to reflect what the product actually is: `@term-ui/core` → `@term-ui/dom` → `@term-ui/react` (+ `@term-ui/shared`).

## What Changes

- Remove the Effect experiment: delete untracked `packages/core/js/effect.ts` and `packages/core/js/effect.test.ts`, revert the `effect`/`@effect/*` dependency additions in `packages/core/package.json`, and regenerate/revert `pnpm-lock.yaml`.
- Keep the trivial `packages/core/src/wasm.zig` whitespace diff or drop it — either way, leave the tree clean.
- Re-commit the `tmp` work on `block-layout` with real commit messages (interactive history editing is optional; at minimum, stop the "tmp" pattern going forward).
- **Remove or explicitly park non-product directories**: `packages/cssom` (advanced but never integrated — park, do not delete, it may be mined later for the styling story), `packages/app`, `packages/asciinema2svg`, `packages/zigbench` (not workspace packages; delete or move out), `packages/devtools` (experiment; park).
- Delete confirmed-dead source: `packages/core/src/tree/Selection_old.zig`; stray files like `tmp.html`, `tmp.debug_whitespace copy.html`, `test.log`.
- Write a minimal root `README.md` (currently empty) stating the product vision and which packages are the product, so scope is recorded in the repo itself.

## Capabilities

### New Capabilities

None — this is pure workspace hygiene; no runtime behavior changes.

### Modified Capabilities

None.

## Impact

- `packages/core/package.json`, `pnpm-lock.yaml` (revert Effect deps)
- `packages/cssom`, `packages/app`, `packages/asciinema2svg`, `packages/zigbench`, `packages/devtools` (parked/removed)
- `packages/core/src/tree/Selection_old.zig` and stray temp files (deleted)
- Root `README.md` (created)
- No behavior changes to core/dom/react.

## Context (for future sessions)

Product vision: developing a CLI with React should feel as natural as the browser — a miniature browser engine for the terminal. DOM tree → layout tree (block/flex, anonymous boxes) → render list → paint, with browser-grade text handling, selection/caret behavior, and input events. Differentiators over Ink: proper layout (e.g. scrollable regions anywhere), proper event parsing, better text handling than React Native.
