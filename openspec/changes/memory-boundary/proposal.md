# Memory Boundary

## Why

The wasm↔JS boundary currently speaks three ownership dialects at once — borrowed interior pointers (`Node_getText`, `Tree_getChildren`), static scratch buffers (hit-test capped at 512 items), and ownership transfer that the JS side never honors (`freeBuffer` is called zero times in the codebase). This is the source of the `DebugAllocator` leak reports at exit, a latent per-call leak (`Node_getClientRects`), and a dangling-view hazard of the same class as the gradient stack-buffer bug. The upcoming scroll/overflow work needs exactly the API shapes that leak today (per-frame geometry queries, hit tests), so the contract must be fixed first — new exports should be born safe, not audited later.

## What Changes

- Remove the per-frame `tree.dump()` call from `Document.render()` (devtools legacy: serializes the whole DOM every paint into a retained buffer).
- **Reply arena** in the wasm export layer: every transient output (text reads, geometry, hit-test results, dumps) is written into an arena that is reset at the start of the next export call. Contract: *outputs are valid until the next call into wasm; JS never frees.* Replaces both the borrowed-interior-pointer reads and the fixed-size static scratch buffers (removing the silent hit-test truncation).
- **Wrapper-copy guarantee** in the JS schema layer (the valibot choke point): every output is materialized into JS values (decoded strings, plain arrays/objects) before returning to application code. Raw wasm pointers never escape the wrapper. This also makes `memory.grow` view-detachment structurally impossible.
- **Audit the two surviving patterns**: inbound string ownership (JS allocates, callee frees — verify all string-taking exports have their `defer free`) and explicit `dispose()` on long-lived handles (Tree, Renderer, Selection, ByteArrayList).
- **Memory regression gate**: extend the oracle-test harness with a high-water-mark test (hundreds of mutate→layout→paint cycles must return the live-allocation count to baseline) and make `detectLeaks` failures loud in the dom vitest harness.

Out of scope (deliberate): FinalizationRegistry/GC-driven disposal, refcounting, per-frame arena granularity, `getText` copy-cost benchmarking.

## Capabilities

### New Capabilities

- `wasm-boundary`: the ownership and lifetime contract of the wasm↔JS interface — transient outputs via reply arena (valid until next call, never freed by the client), long-lived handles via explicit dispose, inbound argument ownership, and leak-free steady-state operation.

### Modified Capabilities

None (selection/caret-positioning/input-events specs are unaffected; only the transport under them changes).

## Impact

- `packages/core/src/wasm.zig`: export layer (reply arena, removal of static scratch buffers and borrowed-pointer returns)
- `packages/core/js/exportsSchema.ts` + `js/index.ts`: wrapper-copy enforcement
- `packages/dom/src`: call sites simplified (no pointer handling), `Document.render()` dump removal
- New tests: core high-water-mark test, dom leak-check test
- No behavior change visible to applications except bugs removed (truncated hit tests, exit leaks)
