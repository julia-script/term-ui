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

Parked (kept for later, not part of the build): `packages/devtools` (devtools experiment), `packages/docs`.

## Toolchain

The Zig code tracks Zig master, **pinned** to the exact version recorded in `.zigversion` (see `packages/core`). Bump the pin deliberately; never build against an unpinned toolchain.

## Status

Alpha, and stabilized: the engine has a spec'd behavior contract, a rebuilt test
suite (invalidation oracle, layout and paint snapshots, leak gates, input
robustness), and a React renderer on current `react-reconciler`.

Behavior is documented as capability specs in [`openspec/specs/`](openspec/specs) —
selection, caret positioning, input events, the WASM memory boundary,
scroll/overflow, and the React renderer contract. Completed work is archived
under [`openspec/changes/archive/`](openspec/changes/archive).

Expect API churn before 1.0. Terminal support varies by emulator; features that
depend on newer protocols (kitty keyboard, SGR mouse) degrade to legacy
encodings where unavailable.

## Examples

Runnable demos live in [`examples/`](examples) — a chat client with streaming
responses and a multiline editable input, a calculator, multi-pane scrolling
logs, an editable text region, and a counter. Run one with `pnpm start` from its
directory.
