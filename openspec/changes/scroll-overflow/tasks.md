# Tasks: scroll-overflow

## 1. Test-first: pin current behavior

- [x] 1.1 Layout/paint snapshot tests: overflow hidden/scroll/visible clipping, scrolled content at various offsets, nested scroll containers, partial line clipping (rows and columns)
- [x] 1.2 Scroll-state unit tests: clamping, scrollHeight/clientHeight derivation from v2 layout (D2); fix `getScroll*`/`getClient*` if they read stale-era data
- [x] 1.3 Triage failures from 1.1–1.2; fix layout/render-list/canvas gaps until snapshots express the spec

## 2. Invalidation

- [x] 2.1 Add `set_scroll` op to the oracle mutation set (D3); run the battery; fix any incremental-vs-cold divergence

## 3. Input wiring (dom)

- [x] 3.1 Wheel default action: nearest scrollable ancestor from hit chain, clamped scrollBy, preventDefault honored (D4); integration test wheel→scroll and prevented-wheel
- [x] 3.2 PgUp/PgDn keyboard scrolling of the active scroll container; integration test
- [x] 3.3 Geometry under scroll: integration tests for click-lands-on-scrolled-line and clipped-content-not-hit; fix hit testing if needed

## 4. Caret visibility

- [x] 4.1 Caret-into-view after keyboard selection changes and typing (D5); integration test arrow-past-the-fold in a scrollable editable

## 5. React + demo

- [x] 5.1 `overflow` style props through the reconciler; `onScroll` event fires with scroll position
- [x] 5.2 `examples/react-log-pane` acceptance demo; verify under pty (render, wheel scroll, PgUp/PgDn, drag-select inside scrolled content, ticker appends)

## 6. Wrap up

- [x] 6.1 Full suites (zig debug + release-safe, dom vitest incl. leak gate), examples verified; commit
