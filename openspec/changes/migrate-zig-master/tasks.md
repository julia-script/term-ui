# Tasks: migrate-zig-master

## 1. Pin the toolchain

- [x] 1.1 Record the exact installed Zig version in `.zigversion` at repo root
- [x] 1.2 Update `.github/workflows/release.yml` to install/pin that same version

## 2. Shrink the surface (delete before migrating)

- [x] 2.1 Delete old test infrastructure: `packages/core/src/tests/`, `packages/core/src/testing/`, `packages/core/src/tests.zig`, `packages/core/test_snapshots/`, `src/tree/invalidation_test.zig`, `src/tree/selection_snapshot_test.zig`, style test files; remove their references from `wasm.zig`/`main.zig` test blocks
- [x] 2.2 Delete unreferenced v1 layout/renderer code (`src/layout/compute/*` except files still imported by live tree code, `src/renderer/Renderer.zig`, `src/renderer/Canvas.zig`, `src/renderer/gradient.zig`, `src/tree/Cache.zig` if unreferenced) plus vestigial imports (e.g. unused v1 `computeLayout` import in `wasm.zig`); keep shared types still used by `tree/` (`compute_constants.zig`, `text/ComputedText.zig`) for now
- [x] 2.3 Delete standalone demo/bench entry points that reference deleted code (`gradient_interactive.zig`, `gradient_perf.zig`, `playground.zig`) if not wired into `build.zig` targets we keep

## 3. Migrate the build system

- [x] 3.1 Fix `build.zig` for current `std.Build` API; drop build steps for deleted targets

## 4. Compile-fix loop

- [x] 4.1 `zig build wasm` compile-fix iteration until green (std.Io writers, ArrayList unmanaged, usingnamespace, format API, etc.); delete non-compiling inline test blocks instead of porting them
- [x] 4.2 `zig build` (native exe) compile-fix until green
- [x] 4.3 `zig build debugbuild`/test target compiles (with whatever minimal inline tests survived)

## 5. Verify the slice

- [x] 5.1 `pnpm build` in `packages/core` produces `dist/` with fresh wasm; dom/react typecheck still passes
- [x] 5.2 Run an example/demo to confirm rendering works post-migration; note any behavioral drift observed

## 6. Wrap up

- [x] 6.1 Commit with descriptive message(s); record known-deferred items (shared v1 types to fold into v2 later) in the change notes
