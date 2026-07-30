# Tasks: Modernize React Renderer

## 1. Upgrade dependencies

- [x] 1.1 Verify the published react-reconciler 0.33.0 surface against the doc: check `ReactFiberConfig.custom.js` and feature flags at the matching tag in `~/Documents/dev.nosync/reconciler/react`; note any divergences from the 0.34 doc
- [x] 1.2 Bump catalog: `react-reconciler: 0.33.0` (exact), `react: ^19.2.0`, `react-dom: ^19.2.0`, `@types/react`/`@types/react-dom` to match; `pnpm install`
- [x] 1.3 Vendor the researched d.ts as `packages/react/src/reconciler/react-reconciler.d.ts`, delete `reconciler-types.d.ts`, fix any compile fallout

## 2. Rewrite the host config

- [x] 2.1 Delete `logCalls`, the log-file stream, `stringify`, commented dead code, and mid-file imports
- [x] 2.2 Rebuild the config on the doc §6 skeleton: keep existing create/append/insert/remove/text logic; add `shouldAttemptEagerTransition`, full suspensey family, view-transition stubs (sync callback contract), fragment-ref stubs, profiling trio, `preparePortalMount`, `insertInContainerBefore`, `commitMount`, `resetTextContent`, form sentinels, DevTools identity fields
- [x] 2.3 Fix the priority slot: init `NoEventPriority`, `resolveUpdatePriority` never returns it
- [x] 2.4 `commitUpdate`: diff `contentEditable` in addition to style and event handlers
- [x] 2.5 `detachDeletedInstance`: dispose the instance (verify no double-free with dom-layer teardown; guard with `isDisposed()`)

## 3. Suspense visibility

- [x] 3.1 Add a hidden flag to the DOM layer (element + text) that removes the node from layout/paint/hit-testing without touching its style string
- [x] 3.2 Implement `hideInstance`/`unhideInstance`/`hideTextInstance`/`unhideTextInstance` on that flag

## 4. Priority wiring & error routing

- [x] 4.1 Bracket event dispatch in the react package: discrete for key/click/mousedown/mouseup, continuous for mousemove/wheel/scroll, restore after dispatch (dom package stays react-free)
- [x] 4.2 TermUi error handlers: queue errors while the alternate screen is active, flush after restore; uncaught errors dispose the terminal before reporting
- [x] 4.3 `createContainer` 11-arg cleanup (`""` prefix, proper transition-indicator arg) and `injectIntoDevTools()` after creation

## 5. Tests & verification

- [x] 5.1 `packages/react/src/reconciler.test.tsx`: mount/update/reorder/unmount against painted output; event-handler swap; contentEditable toggle
- [x] 5.2 Unmount-dispose leak gate (mount/unmount N cycles, steady native memory)
- [x] 5.3 Suspense hide/restore test; `startTransition` commit test; priority bracket test
- [x] 5.4 Full suite green: `pnpm vitest` in dom+react packages, `zig build test`, run the react-log-pane and calculator examples by hand
