# Modernize React Renderer

## Why

The react-reconciler host config in `packages/react` was written blind against outdated docs (≤0.28-era README) and carries debug scaffolding, no-op stubs, and commented-out lifecycle code. We now have a code-verified reference for the current API (`~/Documents/dev.nosync/reconciler/`: docs + hand-written d.ts verified against facebook/react main, react-reconciler 0.34 / React 19.3). Upgrading to the latest published reconciler (0.33.0, React 19.2.x) makes several currently-missing host-config methods mandatory (view transitions and fragment refs are on by default), so the upgrade and the fixes are one change.

## What Changes

- Pin `react-reconciler` to 0.33.0 and `react` to 19.2.x in the workspace catalog.
- Replace the hand-rolled `reconciler-types.d.ts` (based on ≤0.28 docs) with the researched d.ts for the current API.
- Complete the host config per the verified reference: `shouldAttemptEagerTransition`, full suspensey-commit family, view-transition stub contract (mutation/layout/spawned-work callbacks run synchronously), fragment-ref stubs, profiling trio, `preparePortalMount`, `insertInContainerBefore`, `commitMount`, form plumbing sentinels, text hide/unhide.
- **BREAKING (internal)**: remove the `logCalls` debug wrapper that writes `./reconciler.log` into the consumer's cwd at import time, plus dead code (`stringify`, commented `NodeWithProps`, mid-file `node:fs` imports).
- Fix real behavior bugs:
  - `detachDeletedInstance` now disposes unmounted host instances (wasm handle leak today).
  - `hideInstance`/`unhideInstance` actually hide/show (Suspense fallbacks over mounted content are visually broken today).
  - Update-priority slot follows the contract (`NoEventPriority` initial, `resolveUpdatePriority` never returns it).
  - `commitUpdate` diffs `contentEditable`, not just style and event handlers.
  - Root error handlers route through a terminal-safe error surface instead of raw `console.error` onto the alternate screen.
- Wire input dispatch to update priorities: keys/clicks at `DiscreteEventPriority`, mouse-move/wheel at `ContinuousEventPriority`.
- Support `injectIntoDevTools()` via the three host-config identity fields.
- New reconciler integration test suite: mount/update/reorder/unmount, unmount-dispose leak gate, Suspense hide/unhide, transition commit does not crash.

## Capabilities

### New Capabilities
- `react-renderer`: the react-reconciler host-config contract — instance lifecycle (create/append/insert/remove/dispose), update semantics (style, contentEditable, event handlers, text), visibility for Suspense, update-priority model tied to input events, error surfacing, and the stub contracts (view transitions, fragment refs, suspensey commits) required by the current reconciler.

### Modified Capabilities
- `input-events`: held keys must repeat (autorepeat events were dropped), modifier chords must not produce text, a bare line feed means shift+enter rather than Ctrl+J, and empty lines (including a trailing line break) must be caret-addressable and traversable by vertical arrows.

## Impact

- `packages/react/src/reconciler/reconciler.ts` — rewritten host config.
- `packages/react/src/reconciler/reconciler-types.d.ts` — replaced.
- `packages/react/src/TermUi.tsx` — createContainer arg cleanup, error routing, DevTools injection.
- `pnpm-workspace.yaml` catalog + lockfile — react 19.2.x, react-reconciler 0.33.0.
- New test file(s) in `packages/react/src/`.
- `packages/dom/src/InputManager.ts`, `packages/core/src/cmd/input/manager.zig` — repeat/chord/line-feed key semantics.
- `packages/core/src/layout/v2/line-builder/{compute,wrap}.zig`, `packages/core/src/tree/Selection.zig` — preserved segment breaks and empty-line caret navigation.
- `examples/react-chatbot` — multiline chat input demo exercising the above.
- Ref surface unchanged: `getPublicInstance` keeps exposing the DOM `Element` (browser-like).
