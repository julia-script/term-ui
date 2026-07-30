# Tasks: stabilize-selection-input

## 1. Selection.modify: alter + word granularity (core)

- [x] 1.1 Add `Alteration` (move/extend) to `Selection.modify` with browser-consistent move semantics (D1); update the `Selection_modify` wasm export and all core callers
- [x] 1.2 Implement `word` granularity using `uni/WordBreak.zig` (D2), forward and backward, crossing node boundaries
- [x] 1.3 Extend selection snapshot tests with alter=move and word steps; suite green

## 2. Caret-from-point verification (core)

- [x] 2.1 Unit tests for `Tree.caretPositionFromPoint` per spec scenarios (grapheme halves, past end of line, empty-space fallback); fix fallback behavior where it diverges from the spec

## 3. DOM layer (TS)

- [x] 3.1 Update `packages/dom` `Selection.modify` + exports schema for the new alter parameter
- [x] 3.2 Default-actions controller in `Document.ts` (D3): click→caret, drag→select, keyboard mapping (arrows/shift/word-modifier/home/end), honoring `preventDefault`
- [x] 3.3 dom vitest integration test: raw bytes → InputManager → Document → wasm selection state for click-to-caret and shift+arrow-extend

## 4. Acceptance demo

- [x] 4.1 `examples/react-editable`: editable text region demo (D4) exercising click/drag/keyboard selection with wrapped text; verify it runs

## 5. Wrap up

- [x] 5.1 Full test suite + dom vitest green; commit
