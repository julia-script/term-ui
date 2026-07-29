# Stabilize Selection & Input

## Why

The product's core promise is that a terminal UI feels as natural as the browser — and the user-facing surface of that promise is selection, caret positioning, and input handling. These are the most cross-cutting features in the engine: selection reads through the DOM tree (boundary points), the layout tree (line boxes, word/line granularity), the render list (geometry, hit testing), and assumes every cache is fresh. History shows the pain concentrated here ("fixed selection overwritting text", "fix hang issue"). With invalidation verified by the oracle tests, this change makes selection/caret/input behavior correct and browser-natural, and finishes with an acceptance demo that makes "usable and releasable" falsifiable.

## What Changes

- Fix selection bugs surfaced by the new selection snapshot tests; bring `Selection.modify` (character/word/line granularities, extend/collapse) to browser-consistent behavior.
- Caret positioning: implement/verify the WebKit-style `caretPositionFromPoint` fallback semantics (nearest reasonable caret instead of null) already analyzed in `webkit-caretPositionFromPoint-implementation.md`.
- Input pipeline stabilization across the stack: `core/src/cmd/` (CSI/OSC/terminfo parsing, key handling) and `packages/dom` `InputManager` → DOM event dispatch (`addEventListener` semantics), so keyboard-driven caret/selection movement works end to end from real terminal input.
- Decide and document mouse scope for the first release (click-to-place-caret and drag-to-select are the natural minimum given the caret-from-point work; full mouse support may follow).
- **Acceptance demo**: a React (`@term-ui/react`) example rendering an editable/selectable text region — click to place the caret, drag to select, shift+arrow and word-jump to extend, selection highlight correct across wrapped lines. This demo is the release bar: every layer of `terminal → core(wasm) → dom → react` sits under it.

## Capabilities

### New Capabilities

- `selection`: browser-consistent selection model — boundary points, ranges, `modify` granularities, collapse/extend, deletion — over the two-tree architecture.
- `caret-positioning`: caret-from-point with WebKit-style nearest-position fallback; caret geometry queries for rendering.
- `input-events`: terminal input (keys, and mouse to the decided scope) parsed and dispatched as DOM-style events through `packages/dom`.

### Modified Capabilities

None (no existing specs yet; these are the first).

## Impact

- `packages/core/src/tree/` (Selection, Range, BoundaryPoint), `packages/core/src/layout/v2/` (RenderList queries), `packages/core/src/cmd/`
- `packages/dom` (InputManager, event types, dispatch), `packages/react` (demo app, possibly small reconciler fixes)
- `examples/` gains the acceptance demo
- Depends on: `migrate-zig-master`, `rebuild-test-suite` (oracle invalidation tests green first — many "selection bugs" are invalidation bugs wearing a costume).
