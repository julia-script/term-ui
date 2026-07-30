# Tasks: rebuild-test-suite

## 1. Snapshot infrastructure on the new toolchain

- [x] 1.1 Resurrect the snapshot helper from git history as `src/testing/snapshot.zig`, migrated to new APIs (file IO via the runner's `std.Io` instance, unmanaged ArrayList, `test_options.update` instead of env vars); file snapshots + inline snapshots both working
- [x] 1.2 Expose `test_io`/`test_options` as `pub` from `test_runner.zig`; verify the `-Dupdate` flow regenerates snapshots end to end; update CLAUDE.md's snapshot command if it changed

## 2. Invalidation oracle tests (headline)

- [x] 2.1 Add `src/tree/invalidation_oracle_test.zig` (referenced from the `wasm.zig` test block): seeded PRNG mutation sequences (append/remove nodes, text edits, style changes) applied incrementally with caching, compared after every mutation against a cold-built tree from the same DOM state; any divergence fails with the seed + mutation log
- [x] 2.2 Run the oracle across a battery of seeds; file/fix or document any invalidation bugs it finds (finding bugs is success, not failure)

## 3. Layout + selection snapshot tests

- [x] 3.1 Fresh layout snapshot tests via `docFromXml` (nodes as inputs per CLAUDE.md): block flow, flex, anonymous-box generation, wrapping/whitespace/alignment
- [x] 3.2 Selection snapshot tests: `Selection.modify` across character/word granularities on wrapped text, rendered via `Range.formatTree` caret/range markers

## 4. TS test suites

- [x] 4.1 Existing `packages/dom` vitest suite runs green (fix breakage if any)

## 5. CI

- [x] 5.1 Add a test job to the GitHub workflow: `zig build test` in core + vitest where present

## 6. Wrap up

- [x] 6.1 Full suite green (or failures documented as known bugs); commit
