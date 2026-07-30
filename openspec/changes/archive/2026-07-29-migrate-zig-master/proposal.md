# Migrate to Zig Master (Pinned)

## Why

The project is built against Zig `0.15.0-dev.589+23c817548` (mid-2025 master, per CI cache key). The locally installed toolchain is `0.17.0-dev.1503+1f1bee62e` (source build at `~/zig`), two release cycles ahead, and `zig build` fails on the first API touched in `build.zig`. Nothing can be built, run, or tested until this is resolved. The unpinned-toolchain drift is also *how the project died last time* — the migration must end with the toolchain pinned so hibernation is survivable.

## What Changes

- Migrate all Zig code in `packages/core` (~54k LOC, minus deleted tests — see below) to the current Zig master, covering the breaking changes since 0.15-dev: `std.Io` reader/writer rework ("writergate"), unmanaged-by-default `ArrayList`, `usingnamespace` removal, format-API changes, `std.Build` API changes, and whatever else the compiler surfaces.
- **Delete the existing test suite as part of the migration instead of porting it** (decision: existing tests are untrusted and would be rewritten anyway — see `rebuild-test-suite`). This includes `test_snapshots/`, `src/testing/`, `src/tests/`, `src/tree/invalidation_test.zig`, `src/tree/selection_snapshot_test.zig`, and inline `test` blocks that don't compile trivially. Do not spend migration effort making old tests pass.
- Delete the dead v1 pipeline before migrating it: `src/layout/compute/`, `src/renderer/Renderer.zig` + v1 renderer files, `src/tree/Cache.zig` (imports v1 `layout/compute`) — after confirming `wasm.zig` and `main.zig` only reach the v2 path. Shrinking the surface first means never paying migration cost on dead code.
- **Pin the toolchain**: record the exact master commit/version in the repo (e.g. `.zigversion`), reference it from `build.zig.zon` `minimum_zig_version` if applicable, and update `.github/workflows/release.yml` (`mlugg/setup-zig`) to the same pin. Bumping the pin becomes a deliberate, recurring chore — never ambient drift.
- Definition of done: `zig build` and `zig build wasm` succeed on the pinned master; the demo/examples render; JS build (`pnpm build`) still passes in `core`.

## Capabilities

### New Capabilities

None — behavior-preserving toolchain migration. (Known risk: with the old tests deleted and no trusted baseline, behavioral regressions during migration are only caught by demos/examples. Accepted trade-off; `rebuild-test-suite` must follow immediately.)

### Modified Capabilities

None.

## Impact

- All of `packages/core/src/**/*.zig`, `build.zig`, `test_runner.zig`
- Deleted: v1 layout/renderer path, old test infrastructure
- CI: `.github/workflows/release.yml` Zig pin
- New: `.zigversion` (or equivalent pin record)
- `packages/dom`/`react` unaffected except for a rebuilt `core.wasm`.
