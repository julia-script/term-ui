# term-ui

A miniature browser engine for the terminal. The goal: building a CLI with React should feel as natural as building for the browser.

Like a browser, term-ui runs a real pipeline — DOM tree → layout tree (block/flex, anonymous boxes) → render list → paint — with browser-grade text handling (whitespace rules, wrapping, alignment), selection and caret behavior (including WebKit-style caret-from-point), and terminal input parsed into DOM-style events. Things Ink can't give you — like a scrollable region anywhere on screen, or drag-to-select text — fall out of the architecture instead of being bolted on.

## Packages

The product is the vertical slice:

| Package | What it is |
|---|---|
| [`@term-ui/core`](packages/core) | The engine, written in Zig, compiled to WASM. DOM tree, layout tree, render list, renderer, text pipeline, selection, terminal input parsing. |
| [`@term-ui/dom`](packages/dom) | TypeScript DOM layer over the WASM core — `Document`, `Element`, `addEventListener`, `Selection`, input manager. |
| [`@term-ui/react`](packages/react) | React reconciler on top of the DOM layer. |
| [`@term-ui/shared`](packages/shared) | Shared utilities. |

Parked (kept for later, not part of the build): `packages/cssom` (CSSOM experiment, advanced but never integrated), `packages/devtools` (devtools experiment), `packages/docs`.

## Toolchain

The Zig code tracks Zig master, **pinned** to the exact version recorded in `.zigversion` (see `packages/core`). Bump the pin deliberately; never build against an unpinned toolchain.

## Status

Under active stabilization. The current plan lives in [`openspec/changes/`](openspec/changes): Zig-master migration → test rebuild (invalidation oracle + selection snapshots) → selection/input stabilization, ending in an editable-text acceptance demo.
