# Rebuild Test Suite

## Why

The old test suite was deleted during the Zig migration by explicit decision: it was untrusted (likely red even on its own toolchain), and its author wasn't proud of the setup. The engine currently runs with **no safety net**, immediately after a 54k-LOC mechanical migration. This change rebuilds testing from scratch against the v2 pipeline only, using modern Zig idioms, and targets the two areas of lowest confidence first: cache invalidation and selection.

## What Changes

- Rebuild snapshot-test infrastructure on the new toolchain, following the conventions already recorded in `CLAUDE.md`: tests inline with code (Zig convention), snapshot tests by default, **nodes as test inputs instead of hardcoded tokens**, all test files referenced from the `wasm.zig` test block, `UPDATE_SNAPSHOTS=true zig build test` to regenerate.
- **Invalidation oracle tests** (highest priority — this is the "when to update the tree cache" confidence gap): apply a randomized/generated sequence of DOM mutations, lay out incrementally with caching enabled, then construct a fresh tree from the same final DOM state and lay out cold. Any difference between incremental and cold layout is an invalidation bug. Failures should report the minimal mutation sequence.
- **Layout snapshot tests** for the v2 pipeline: block, flex, anonymous-box generation, line-builder (whitespace rules, wrap, alignment) — capturing post-migration behavior as the baseline going forward.
- **Selection snapshot tests**: boundary points, `Selection.modify` granularities (character/word/line), caret-from-point behavior (per the WebKit-derived fallback semantics documented in `webkit-caretPositionFromPoint-implementation.md`), selection rendering across wrapped lines.
- Vitest coverage for the TS half of the product where it's load-bearing: `packages/dom` (InputManager, Element/Document event dispatch) and `packages/react` (reconciler basics).
- CI runs the full suite on the pinned Zig.

## Capabilities

### New Capabilities

None in product behavior — this change builds verification for existing behavior. (If writing specs for `layout-invalidation` or `selection` becomes useful while testing clarifies their contracts, add them in `stabilize-selection-input` where behavior actually changes.)

### Modified Capabilities

None.

## Impact

- New inline `test` blocks across `packages/core/src/tree/` and `packages/core/src/layout/v2/`
- New/updated `test_runner.zig`, snapshot directories, `wasm.zig` test block references
- `packages/dom` / `packages/react` vitest suites
- CI workflow gains a test job
- No runtime behavior changes; bugs found here are fixed in follow-up work (or in `stabilize-selection-input` when selection-related).
