# Design: stabilize-selection-input

## Current state (verified in code)

| Piece | State |
|---|---|
| `Tree.caretPositionFromPoint` | Implemented in core (`Tree.zig:2136`), exported to wasm, wrapped in `Document.ts`. Fallback quality untested against the WebKit doc. |
| `Selection.modify` | Extend-only. Granularities: character, line, lineboundary, documentboundary. `word` is a commented-out TODO. Ghost position (horizontal memory) exists. |
| Word segmentation | `src/uni/WordBreak.zig` (UAX-29 style, backed by the unicode DB) — reusable for word granularity. |
| Terminal input parsing | `core/src/cmd/` parses keys (incl. kitty), legacy + SGR mouse; delivered to JS via `emitEvent`. |
| DOM event synthesis | `Document.ts` builds bubbling `MouseEvent`/`KeyboardEvent` with `preventDefault`; an earlier default-actions attempt is commented out. |
| Missing | `alter` (move vs extend) in modify; word granularity; default actions (click→caret, drag→select, keyboard bindings); acceptance demo. |

## Decisions

### D1: Movement semantics live in Zig core

The engine owns all caret/selection movement; the JS layer only translates events into `Selection` calls. `Selection.modify` gains an `Alteration` parameter:

```
modify(tree, alter: enum { move, extend }, direction, granularity, ghost_position)
```

Move semantics (matching browser arrow-key behavior):
- `move` + `character` on a non-collapsed range: collapse to the range's directional edge (forward → end, backward → start), no further movement.
- `move` + any other case: collapse to focus, then apply one unit of movement.
- `extend`: current behavior (anchor fixed, focus moves).

This is a **breaking change** to the `Selection_modify` wasm export (new alter arg); `packages/dom` `Selection.modify` and the exports schema update in lockstep.

### D2: Word granularity via the existing WordBreak segmenter

Word movement reuses `uni/WordBreak.zig` over the same text content the line-builder segments — no second word model. Semantics: forward stops at the end of the current-or-next word; backward stops at the start of the current-or-previous word (skipping intervening whitespace/punctuation runs), crossing node boundaries the same way character movement does.

### D3: Default actions as a small controller in Document.ts

After event dispatch, when `!event.defaultPrevented`:
- `mousedown` (left): `caretPositionFromPoint(x, y)` → collapse selection there; remember "dragging".
- `mousemove` while dragging: `caretPositionFromPoint` → `setFocus` (anchor untouched → drag-select).
- `mouseup`: end dragging.
- `keydown` mapping: Left/Right = character, Up/Down = line; Shift ⇒ extend else move; Alt or Ctrl modifier ⇒ word granularity on Left/Right; Home/End = lineboundary.

Wheel/hover: out of scope (per scope decision — caret + drag select only).

### D4: Acceptance demo = editable text region example

`examples/react-editable`: an `@term-ui/react` app with a bordered, `contenteditable` text region — click places the caret, drag selects, shift+arrows extend, word-jump works, highlight correct across wrapped lines. This demo is the release bar for the vertical slice.

## Testing

- Zig: extend selection snapshot tests with alter=move and word-granularity steps; caret-from-point scenario tests (grapheme halves, past-end-of-line, empty-space fallback) as plain unit tests against `Tree.caretPositionFromPoint`.
- The invalidation oracle already guards the recompute path that selection reads through.
- dom vitest: integration test driving raw input bytes through `InputManager` → `Document` → wasm and asserting selection state (click→caret, shift+arrow→extend).

## Open questions

None — mouse scope resolved (caret + drag select).
