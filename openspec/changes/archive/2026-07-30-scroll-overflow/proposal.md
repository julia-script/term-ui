# Scroll & Overflow

## Why

Scrollable regions anywhere on screen are the original differentiator of this project over Ink — "a scrollable window in the middle of the terminal" was the founding demo idea. The machinery half-exists: overflow styles parse, the render-list builder subtracts `scroll_offset`, push/pop clipping reaches the canvas, `scrollTop/scrollLeft` setters clamp against content size, and the Document layer routes wheel events. But none of it is verified in the v2 pipeline — the v1 scroll tests were deliberately deleted during the Zig migration, so today scroll is untested, unfinished in unknown ways, and unusable with confidence. This change finishes it, proves it, and ships the vision demo on top of the now-safe memory boundary.

## What Changes

- **Overflow behavior in the v2 pipeline**: `overflow: visible | hidden | scroll` respected end to end — content larger than a `hidden`/`scroll` container is clipped at the container's bounds (including partial clipping of text lines), `visible` overflows without clipping.
- **Scroll state correctness**: `scrollTop/scrollLeft` clamped to `scrollHeight/Width − clientHeight/Width`; offsets shift descendant geometry in the render list; invalidation marks repaint (verified by extending the oracle's mutation set with scroll ops).
- **Input wiring**: wheel events scroll the nearest scrollable ancestor under the pointer (verify/fix the existing Document default behavior); programmatic `scrollTop/scrollLeft` from the dom API; PgUp/PgDn scrolling for the hovered/active scroll container.
- **Geometry consistency under scroll**: hit testing, `caretPositionFromPoint`, `getBoundingClientRect`, and selection highlights all operate in viewport coordinates consistent with applied scroll offsets.
- **Caret keeps itself visible**: caret movement inside an editable region within a scrollable container scrolls the caret into view (minimal `scrollIntoView` on selection changes).
- **React surface**: `overflow` style props flow through; `onScroll` fires; the acceptance demo is the founding one — a React app with a scrollable log pane in the middle of the terminal, wheel- and keyboard-scrollable, with selectable text inside.
- **Tests**: layout/paint snapshots for clipped and scrolled content (incl. nested scroll containers), oracle scroll ops, dom integration tests for wheel→scroll and caret-into-view.

Out of scope: rendered scrollbars/indicators, smooth scrolling animation, horizontal wheel tilt mappings beyond what the input layer already parses, `overflow: auto` semantics (treat as `scroll` for now).

## Capabilities

### New Capabilities

- `scroll-overflow`: overflow clipping and scrollable-container behavior — scroll state and clamping, geometry/hit-testing consistency under scroll, wheel/keyboard/programmatic scrolling, and caret visibility in scrollable editables.

### Modified Capabilities

None (selection/caret-positioning specs already describe behavior in viewport coordinates; no requirement text changes).

## Impact

- `packages/core/src/layout/v2` (overflow handling, scroll geometry), `renderer/v2` (clip verification), `src/tree/Node.zig` (scroll API), `src/wasm.zig` (scroll exports — written against the reply-arena pattern)
- `packages/dom` (wheel default behavior, scroll API, caret-into-view), `packages/react` (style props, onScroll, demo)
- New snapshot/oracle/integration tests; `examples/react-log-pane` acceptance demo
