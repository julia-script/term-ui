# Design: Modernize React Renderer

## Reference material

- `~/Documents/dev.nosync/reconciler/docs/react-reconciler.md` — code-verified API reference (targets main / 0.34; we pin the latest published 0.33.0). §6 has the minimal working config; the errata table lists the API breaks vs old docs.
- `~/Documents/dev.nosync/reconciler/types/react-reconciler.d.ts` — hand-written d.ts for the current API; vendor it as our module declaration.
- `~/Documents/dev.nosync/reconciler/react/` — the clone. When 0.33 differs from the doc, `packages/react-reconciler/src/forks/ReactFiberConfig.custom.js` at the `v19.2.x` tag is authoritative. Re-verify the feature-flag matrix (§8) against that tag before relying on it.

## Decisions

**One rewrite, not incremental patching.** `reconciler.ts` is small (~430 lines, half dead). Rewrite it around the doc's §6 minimal config, keeping our existing create/append/update logic where it's already right.

**Versions.** Catalog: `react-reconciler: 0.33.0` (exact — the reconciler doesn't follow semver vs React; every minor can break the host contract), `react: ^19.2.0`, `@types/react: ^19.2`. Verify peer range of the published 0.33.0 at upgrade time.

**Types.** Copy the researched d.ts into `packages/react/src/reconciler/react-reconciler.d.ts`, replacing `reconciler-types.d.ts`. Keep it as an ambient module declaration (same mechanism as today). If the 0.33-published surface differs from the d.ts (built for main), adjust the vendored copy and note the divergence at the top.

**Priority slot.** Module-level slot initialized to `NoEventPriority`. `resolveUpdatePriority()` returns the slot unless it is `NoEventPriority`, then `DefaultEventPriority`. Input wiring: `Document.onInput` (the single dispatch entry) brackets dispatch in `setCurrentUpdatePriority(...)`/restore — discrete for key/mousedown/mouseup/click, continuous for mousemove/wheel/scroll. Import constants from `react-reconciler/constants` in the react package only; the dom package stays react-free — so the bracket lives in the react package (wrap the subscriber TermUi registers, or expose a pre/post dispatch hook on Document). Keep dom react-free.

**Dispose on detach.** `detachDeletedInstance` runs in the passive phase after React fully detached the node — call `instance.dispose()` guarded by `isDisposed()`. Children: React only calls `removeChild` for the topmost deleted node but calls `detachDeletedInstance` for every deleted host instance, so per-instance dispose is correct and complete. Verify dispose of a child after its parent was disposed is safe (tree may already have freed the subtree) — if not, guard via `isDisposed()`/liveness check on the wasm side.

**Hide/unhide.** (Revised during implementation.) No DOM/Zig change needed: the reconciler is the only writer of style strings for react apps, so it tracks the last-applied style per instance (WeakMap) and a hidden flag (WeakSet), composing `;display: none` onto the style when hidden. `display: none` is fully supported by the layout engine (removed from layout, paint, and hit-testing). Text instances hide via `setText("")`; `unhideTextInstance` receives the current text from React, and `commitTextUpdate` is a no-op while hidden so updates can't un-blank a hidden text node.

**View transitions / fragment refs / suspensey commits.** Stub per the doc's contracts: `startViewTransition` runs `mutationCb(); layoutCb(); spawnedWorkCb(); return null`. Fragment instance: `createFragmentInstance: () => null` + no-ops. Suspensey family: trivial implementations (`maySuspendCommit*: false`, `waitForCommitToBeReady: () => null`, etc.). No behavior, just contract compliance.

**Error routing.** `TermUi` owns the terminal, so it supplies the root error handlers: uncaught → dispose/restore screen, then print error and re-throw (process exits unless the user handled it); caught (error boundary exists) → defer logging until the terminal is restored or write to `process.stderr` only when not on the alternate screen. Keep it minimal: a small `reportError(error, kind)` on TermUi that queues while alternate screen is active and flushes on dispose.

**createContainer.** Use the documented 11-arg form: `null` hydrationCallbacks, StrictMode from env as today, `null` for the ignored override, `""` identifierPrefix (no reason for `"id"`), the three TermUi error handlers, `() => {}` onDefaultTransitionIndicator, `null` transitionCallbacks. Call `injectIntoDevTools()` after container creation; identity fields (`rendererVersion` from package.json version, `rendererPackageName: "@term-ui/react"`, `extraDevToolsConfig: null`) live in the host config.

**What we deliberately skip** (flag-gated off or N/A for terminals): hydration, resources/hoistables, singletons, test selectors, gesture transitions, form actions (sentinel plumbing only — `NotPendingTransition: null`, a null-valued `HostTransitionContext` object, no-op `resetFormInstance`).

## Testing

New `packages/react/src/reconciler.test.tsx` (vitest, headless Document like the dom suites), rendering through the real `TermUi`/reconciler:

- mount/update/reorder/unmount snapshot-ish assertions on painted output
- unmount-dispose leak gate: mount/unmount a subtree N times, assert native memory steady state (reuse the `memory.test.ts` pattern / debug-wasm leak check)
- event handler swap: old handler stops firing
- contentEditable toggle after mount
- Suspense: fallback over mounted content hides and restores (drive with a manually-resolved promise)
- `startTransition` update commits without throwing
- priority: click-driven update flushes before a pending default-priority update (or at minimum: dispatch brackets set/restore the slot correctly)

## Findings from implementation (divergences from the reference doc)

Verified against the published `react-reconciler@0.33.0` bundle (`$$$config.*` reads):

- **`detachDeletedInstance` fires only for host components** (`fiber.tag === 5`), never text fibers — the doc's "every deleted host instance" overstates it. Text instances must be freed by their parent element's detach (we dispose direct `TextElement` children there) and in `removeChild`/`removeChildFromContainer` for topmost-deleted text.
- **`getRootHostContext` must return a non-null sentinel.** The 0.33 dev build logs "Expected host context to exist" and destabilizes retry renders when the context is `null`. We return a module-level `NO_CONTEXT = {}`.
- **The view-transition family is read but never called in 0.33** (`$$$config.startViewTransition;` is a bare discard). The stubs are inert today and become live on 0.34.
- **`measureInstance`, `applyViewTransitionName`, `wasInstanceInViewport`, `addViewTransitionFinishedListener`, `afterActiveInstanceBlur` are absent from the 0.33 surface** (main-only). Providing them is harmless and forward-compatible.
- **Suspense retry commits are throttled** (`FALLBACK_THROTTLE_MS` = 300ms): a commit replacing a recently-shown fallback is deferred via `scheduleTimeout`. Tests must wait ~400ms after resolving a suspended promise.

## Risks

- 0.33-published vs main-doc divergence: mitigated by checking the tag in the clone; the d.ts check harness (`types/check/`) can be run against the vendored copy.
- `react-dom` catalog also bumps to 19.2.x — the dom/react packages must stay version-aligned with react (peer deps).
- Disposing instances on detach could double-free if the dom layer's `removeChild` already tears down — verify current `dispose()` semantics before enabling (the leak exists precisely because this was unclear; settle it with the leak gate test).
