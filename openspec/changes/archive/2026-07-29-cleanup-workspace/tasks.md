# Tasks: cleanup-workspace

## 1. Remove the Effect experiment

- [x] 1.1 Delete `packages/core/js/effect.ts` and `packages/core/js/effect.test.ts`
- [x] 1.2 Revert `packages/core/package.json` and `pnpm-lock.yaml` to HEAD (drops `effect`/`@effect/*` deps)
- [x] 1.3 Revert the stray whitespace diff in `packages/core/src/wasm.zig`

## 2. Prune and park non-product directories

- [x] 2.1 Verify nothing imports `packages/app`, `packages/asciinema2svg`, `packages/zigbench`; delete them
- [x] 2.2 Keep `packages/cssom` and `packages/devtools` in place, marked as parked (documented in README, not in the workspace build path)

## 3. Delete dead files

- [x] 3.1 Verify no imports of `packages/core/src/tree/Selection_old.zig`; delete it
- [x] 3.2 Delete stray temp files: `packages/core/tmp.html`, `packages/core/tmp.debug_whitespace copy.html`, `packages/core/test.log`, root `test.log`

## 4. Record vision and scope

- [x] 4.1 Write root `README.md`: product vision (browser-grade React for the terminal), product packages (core/dom/react/shared), parked packages, toolchain note

## 5. Commit properly

- [x] 5.1 Check whether `block-layout` is pushed to a remote; if local-only, squash the two `tmp` commits into one descriptive commit, otherwise leave history and note it
- [x] 5.2 Commit the cleanup plus workspace tooling (`CLAUDE.md`, `.claude/`, `openspec/`) with descriptive messages
