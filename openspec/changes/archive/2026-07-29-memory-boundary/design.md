# Design: memory-boundary

## Current state (verified)

- 107 exports in `wasm.zig`; three coexisting ownership conventions:
  - Borrowed interior pointers: `Node_getText` (node's text bytes), `Tree_getChildren` (children `ArrayList.items.ptr`), `Node_getAttribute`.
  - Static scratch: `HIT_TEST_LIST_RESULT_BUFFER: [1024]u32` (512-item cap), `boundary_point_buffer`, `client_rect_buffer`, `point_buffer`, `dump_array_list` (grow-only, retained).
  - Transfer: inbound strings (17 `defer freeNullTerminatedBuffer` sites — callee frees); outbound `Node_getClientRects` allocates per call and JS never frees (latent leak, currently no callers).
- JS never calls `freeBuffer`/`freeNullTerminatedBuffer` — outbound transfer is a fiction today.
- `Document.render()` calls `tree.dump()` per frame (devtools legacy) — per-frame full-DOM serialization into the retained `dump_array_list`.
- Core internals are leak-clean per-test (leak-checking allocator in the test runner, 115 tests green).

## D1: Reply arena, reset per export call

A module-level `std.heap.ArenaAllocator` in `wasm.zig`. Every export that returns transient data:

1. resets the arena at entry (`_ = reply_arena.reset(.retain_capacity)`),
2. builds its output with the arena allocator,
3. returns the pointer (length via paired export or inline length prefix, matching each existing call signature).

Reset-at-entry (not exit) is what makes the contract "valid until the *next* call" — the returned buffer survives the return, dies on the next entry. `retain_capacity` keeps steady-state allocation-free after warm-up. Statics (`HIT_TEST_LIST_RESULT_BUFFER` etc.) and borrowed-pointer returns are replaced by arena copies; `Node_getClientRects`'s transfer-alloc becomes an arena alloc (leak class gone).

Only exports *returning transient data* touch the arena; pure mutators skip it (their entry reset would still be correct but pointless — implement reset as a helper called by the returning exports, keeping mutators zero-cost).

## D2: Wrapper-copy in the schema layer

`exportsSchema.ts` transforms already wrap every export. Outputs that are pointers gain a `transform` that reads wasm memory immediately and produces JS values (`TextDecoder` for strings, `Array.from` on typed-array views for numeric buffers). `packages/dom` call sites that currently build views themselves (`TextElement.getText`, hit-test readers, `Tree_getChildren` consumers) shrink to using the wrapper's value directly. After this, `module.memory` handling exists only inside `js/index.ts`/`exportsSchema.ts`.

## D3: Leak gates

- Core: high-water-mark test in the oracle harness — N warm-up cycles, record live-allocation count (`std.testing.allocator` is already leak-checking; expose a counter via the DebugAllocator instance), run hundreds of mutate→layout→paint cycles, assert the count returns to the warm-up baseline.
- dom: a vitest that runs a full document lifecycle against the **debug** wasm and asserts `detectLeaks()` reports clean after dispose. `detectLeaks` currently returns a bool the caller ignores; the test asserts on it (and `dispose()` keeps calling it for dev-time reporting).

## D4: What stays

- Inbound-string convention unchanged (callee frees; audit confirms every string-taking export has its `defer`).
- Explicit `dispose()` for long-lived handles unchanged (audit completeness: Renderer deinit frees canvas + render_buffer; ByteArrayList; Selection via Tree).
- No FinalizationRegistry / refcounting — explicit disposal is honest and sufficient for TUI apps.

## Risks

- Signature drift: some exports return bare pointers with lengths from paired calls (`Node_getText`/`Node_getTextLength`). Copying in the wrapper must pair them correctly — the length call must happen *before* the pointer's next-call window closes. Wrapper composes both calls internally in the right order.
- `emitEventFn`'s event buffer is a static consumed synchronously by the JS event shim during `Tree_consumeEvents` — it is *not* a reply-arena case; leave it (document as an internal invariant).
- Debug-wasm leak test adds a second wasm load to vitest — module init is memoized per dev flag; verify the two instances coexist.
