# Design: scroll-overflow

## Current state (verified in code, none of it tested)

- Styles: `overflow`/`overflow-x`/`overflow-y` parse (`src/styles/overflow.zig`, `parse-styles.zig`).
- Render list: `push_clip`/`pop_clip` items exist; `RenderListBuilder` emits them and subtracts `doc_node.scroll_offset` from descendant absolute positions (lines ~414/478); `Canvas` maintains a clip stack and applies clip rects.
- Node API: `scroll_offset` field; `get/setScrollTop/Left` with clamping against `getScroll{Height,Width} − getClient{Height,Width}`; `canScroll(direction, delta)`.
- wasm exports exist for scroll get/set/canScroll; `Document.ts` routes wheel events and has a `findScrollableAncestor`-style walk (`Node_canScroll` probing) plus a wheel default-behavior branch.
- v1 had scroll tests (`src/tests/scroll.zig`, deleted in the migration); v2 has zero coverage.

Implication: this change is **verify-and-finish**, not greenfield. Expect the unknowns to be in: `scrollHeight` derivation from v2 layout (content extent vs. box), clip correctness for partially visible lines, hit-testing through clip regions, and the wheel default-action path (which predates the drag-state-machine rework).

## D1: Test-first verification

Write the snapshot/oracle/integration tests against the spec *before* fixing anything. Each failure localizes a gap; fixes follow the tests. This mirrors how the selection change worked (snapshots caught the word-overshoot before it shipped) and avoids re-deriving what already works.

## D2: Scroll geometry from the layout tree

`scrollHeight/Width` must come from the v2 layout node's content size (`content_size` in the box output), not from summing children. `clientHeight/Width` = box size minus borders/padding. Verify `Node.getScrollHeight` reads the v2 path; fix if it still reads v1-era data.

## D3: Oracle extension

Add a `set_scroll` op (random scrollable target, random offset) to the oracle mutation set. Requires the oracle's live-node walk to know which elements are scrollable (has overflow style + content larger than box) — pick from styled candidates and rely on clamping for validity. This is the mechanical answer to "does scrolling invalidate correctly."

## D4: Wheel default action placement

Wheel handling follows the mouse-defaults pattern established in the drag-state-machine fix: physical facts (wheel delta) tracked pre-dispatch is unnecessary here (no latch state); the default action after dispatch finds the nearest scrollable ancestor from the hit-test chain (deepest-first), applies `scrollBy` (clamped), requests paint. `preventDefault` skips it. PgUp/PgDn: keyboard default action scrolls the *active* scroll container (the nearest scrollable ancestor of the selection anchor, else the deepest scrollable under the last pointer position, else none).

## D5: Caret-into-view

After selection-changing default actions (keyboard modify, typing) — not after mouse placement (the click was already at a visible point) — walk scrollable ancestors of the focus; for each, if the caret's rect (via `getBoundaryPointPosition`) lies outside the visible region, adjust that ancestor's offset by the minimal delta. One level at a time, innermost first. Implemented in the dom layer using existing geometry exports (all reply-arena safe now).

## D6: New exports follow the reply-arena pattern

Any new geometry/scroll query added during this change allocates from the reply arena; no new statics, no borrowed pointers (per the wasm-boundary spec).

## Acceptance demo

`examples/react-log-pane`: centered bordered pane, ~40×12, containing a few hundred generated log lines; wheel and PgUp/PgDn scroll it; text inside is selectable (drag across scrolled content); a ticker appends lines to prove repaint + scroll position stability (stick-to-bottom NOT required — out of scope).

## Risks

- `content_size` in v2 may not include overflowing children for block layouts (Taffy-derived layouts sometimes track only in-flow content); if so, scrollHeight is wrong and needs a content-extent pass.
- Partial line clipping at cell granularity: a text row half-inside the clip must render only the inside cells; the Canvas clip is rect-based so this should hold, but snapshot tests must pin rows AND columns.
- The wheel path predates several Document.ts reworks this session; assume bitrot until a test proves otherwise.
