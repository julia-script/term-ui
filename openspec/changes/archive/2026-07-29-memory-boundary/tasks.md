# Tasks: memory-boundary

## 1. Freebies and audit

- [x] 1.1 Remove `tree.dump()` from `Document.render()`; verify examples still paint
- [x] 1.2 Audit inbound string ownership: every string-taking export has its `defer free`; fix any missing
- [x] 1.3 Audit long-lived handle disposal (Tree, Renderer, Selection, ByteArrayList): each `deinit` releases everything it owns

## 2. Reply arena (core)

- [x] 2.1 Add the reply arena to `wasm.zig` (reset-at-entry helper, `retain_capacity`); convert borrowed-pointer exports (`Node_getText`, `Tree_getChildren`, `Node_getAttribute`) to arena copies
- [x] 2.2 Convert static-scratch exports (hit-test list, boundary point, client rect, focus position, dump) to arena outputs; remove the fixed buffers and the 512-item hit-test cap
- [x] 2.3 Convert `Node_getClientRects` transfer-alloc to the arena; confirm no export returns wasm_allocator-owned transient memory anymore

## 3. Wrapper-copy (JS)

- [x] 3.1 Schema-layer transforms materialize all pointer outputs into JS values (strings decoded, buffers copied); paired length/pointer exports composed inside the wrapper
- [x] 3.2 Simplify `packages/dom` call sites to consume wrapper values; no `memory.buffer` access outside `js/index.ts`/`exportsSchema.ts`

## 4. Leak gates

- [x] 4.1 Core high-water-mark test: hundreds of mutate→layout→paint cycles return live-allocation count to warm-up baseline
- [x] 4.2 dom vitest: full document lifecycle against debug wasm asserts `detectLeaks()` clean after dispose

## 5. Wrap up

- [x] 5.1 Zig suite (debug + release-safe), dom vitest, examples verified under pty; commit
