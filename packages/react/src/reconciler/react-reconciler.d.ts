/**
 * Hand-written TypeScript definitions for react-reconciler@0.34.0 (React 19.3).
 *
 * Derived from source at facebook/react@6cb4322d65f4c68daa183df24b5f81668cedab14 (main, 2026-07-29):
 *   - Host config surface:  packages/react-reconciler/src/forks/ReactFiberConfig.custom.js
 *   - Public API:           packages/react-reconciler/src/ReactFiberReconciler.js
 *   - Constants:            packages/react-reconciler/src/ReactReconcilerConstants.js
 *   - Reflection:           packages/react-reconciler/src/ReactFiberTreeReflection.js
 *
 * Signatures reflect the reconciler's *call sites*, which are the real contract.
 * Notable differences from @types/react-reconciler (which tracks ≤0.28):
 *   - getCurrentEventPriority is GONE → set/getCurrentUpdatePriority + resolveUpdatePriority
 *   - prepareUpdate/updatePayload are GONE → commitUpdate(instance, type, prevProps, nextProps, handle)
 *   - getChildHostContext(parent, type) and finalizeInitialChildren(instance, type, props, hostContext)
 *     lost their rootContainer parameters
 *   - injectIntoDevTools() takes no arguments (identity comes from host-config fields)
 *   - suspensey-commit methods thread an explicit SuspendedState and are reached by any
 *     transition/retry commit (enableViewTransition is on by default)
 *
 * See docs/react-reconciler.md in this repo for full per-method semantics.
 *
 * @packageDocumentation
 *
 * term-ui note: vendored from ~/Documents/dev.nosync/reconciler/types (built for
 * main/0.34). We pin react-reconciler@0.33.0, where the view-transition family is
 * read but never invoked, a few VT internals (measureInstance,
 * applyViewTransitionName, …) are not read at all, detachDeletedInstance fires
 * only for host components (never text fibers), and getRootHostContext must
 * return a non-null sentinel in dev builds. See
 * openspec/changes/modernize-react-renderer/design.md "Findings".
 */

declare module 'react-reconciler' {
  import type { Component, ReactNode, ReactPortal } from 'react';

  // ---------------------------------------------------------------------------
  // Opaque reconciler-side types
  // ---------------------------------------------------------------------------

  /**
   * A Fiber node — React's internal unit of work.
   *
   * @remarks
   * Host-config methods receive the fiber as their `internalHandle` argument, and
   * the reflection / selective-hydration APIs traffic in fibers. Treat it as an
   * opaque token to pass back to React: its fields change between versions, and
   * reading them forfeits all compatibility guarantees. The few fields typed here
   * exist only because real renderers (react-dom included) need them for
   * instance-to-fiber bookkeeping — not as an invitation to traverse the tree.
   */
  export interface Fiber {
    readonly tag: number;
    readonly key: string | null;
    /** The resolved element type (the host type string for host components). */
    readonly type: any;
    /** Host instance / class instance / null, depending on {@link Fiber.tag | tag}. */
    readonly stateNode: any;
    readonly '__reactFiber-opaque'?: never;
  }

  /**
   * The Fiber passed to {@link CoreConfig.createInstance}, {@link MutationConfig.commitUpdate},
   * {@link MutationConfig.commitMount}, and the hydration methods. Store it on your
   * instance if you need instance → fiber lookup (e.g. for test selectors); never read it.
   */
  export type OpaqueHandle = Fiber;

  /**
   * The FiberRoot returned by {@link Reconciler.createContainer}. Opaque — hold it,
   * pass it back to {@link Reconciler.updateContainer}, and never look inside.
   *
   * @remarks
   * `current` is exposed only because the selective-hydration APIs
   * ({@link Reconciler.attemptSynchronousHydration} and friends) take fibers, and
   * the root fiber is the natural entry point for {@link findCurrentHostFiber}-style
   * traversal via `react-reconciler/reflection`.
   */
  export interface OpaqueRoot {
    /** The root {@link Fiber}. Entry point for the reflection APIs; otherwise opaque. */
    readonly current: Fiber;
    /** The `containerInfo` you passed to {@link Reconciler.createContainer}. */
    readonly containerInfo: any;
    readonly '__reactFiberRoot-opaque'?: never;
  }

  /**
   * A lane bitmask identifying the priority slot an update was scheduled at.
   * Returned by {@link Reconciler.updateContainer}; safe to ignore.
   */
  export type Lane = number;

  /**
   * Update/event priority, as stored and resolved by your host config.
   *
   * @remarks
   * Priorities *are* lane values, so they compare numerically: a lower nonzero
   * number is a higher priority. Only ever use the constants from
   * `react-reconciler/constants` (`NoEventPriority` = 0, `DiscreteEventPriority` = 2,
   * `ContinuousEventPriority` = 8, `DefaultEventPriority` = 32,
   * `IdleEventPriority` = 536870912) — never invent values.
   */
  export type EventPriority = number;

  /**
   * Root mode tag for {@link Reconciler.createContainer}: `ConcurrentRoot` (1) or
   * `LegacyRoot` (0). Legacy mode is compiled out of OSS builds
   * (`disableLegacyMode: true`) — always pass `ConcurrentRoot`.
   */
  export type RootTag = 0 | 1;

  /** Anything renderable: elements, strings, numbers, fragments, arrays, null… */
  export type ReactNodeList = ReactNode;

  /**
   * The shape the reconciler expects for the {@link CoreConfig.HostTransitionContext}
   * host-config field: a raw, hand-built context object (not `createContext` output).
   *
   * @remarks
   * The reconciler writes a form's pending status straight into `_currentValue` /
   * `_currentValue2` while rendering the form host component, and `useFormStatus`
   * reads it back out — the context object is pure plumbing, which is why
   * `Provider`/`Consumer` are `null`. Initialize both value slots to your
   * {@link CoreConfig.NotPendingTransition} sentinel.
   *
   * @example
   * Building the context object for a renderer with no meaningful form status:
   * ```typescript
   * const NotPendingTransition = null;
   * const HostTransitionContext: HostTransitionContext<null> = {
   *   $$typeof: Symbol.for('react.context'),
   *   Provider: null,
   *   Consumer: null,
   *   _currentValue: NotPendingTransition,
   *   _currentValue2: NotPendingTransition,
   *   _threadCount: 0,
   * };
   * ```
   *
   * @typeParam TransitionStatus - Your renderer's form-status value type
   *   (react-dom uses `{ pending, data, method, action }` or its NotPending sentinel).
   */
  export interface HostTransitionContext<TransitionStatus> {
    $$typeof: symbol;
    Provider: null;
    Consumer: null;
    _currentValue: TransitionStatus;
    _currentValue2: TransitionStatus;
    _threadCount: number;
  }

  /** Axis-aligned rectangle returned by the test-selector geometry methods. */
  export interface BoundingRect {
    x: number;
    y: number;
    width: number;
    height: number;
  }

  /**
   * Opaque selector produced by the `create*Selector` factories on {@link Reconciler}
   * and consumed by {@link Reconciler.findAllNodes} & friends.
   */
  export interface TestSelector {
    readonly '__reactTestSelector-opaque'?: never;
  }

  /** Error metadata passed to the root error handlers. */
  export interface ErrorInfo {
    readonly componentStack?: string | null;
  }

  /** {@link ErrorInfo} plus the boundary component that caught the error. */
  export interface CaughtErrorInfo extends ErrorInfo {
    readonly errorBoundary?: Component<any, any> | null;
  }

  /**
   * Observers for Suspense/Activity boundary hydration, passed to
   * {@link Reconciler.createContainer}.
   *
   * @remarks
   * Only consulted behind the `enableSuspenseCallback` flag, which is **off** in
   * OSS builds — pass `null` unless you compile React yourself with it enabled.
   */
  export interface SuspenseHydrationCallbacks<SuspenseInstance, ActivityInstance> {
    onHydrated?: (hydrationBoundary: SuspenseInstance | ActivityInstance) => void;
    onDeleted?: (hydrationBoundary: SuspenseInstance | ActivityInstance) => void;
  }

  /**
   * Transition Tracing observers, passed to {@link Reconciler.createContainer}.
   *
   * @remarks
   * Dead code in OSS builds (`enableTransitionTracing` is off) — pass `null`.
   * Typed for completeness so www-style builds can use the same definitions.
   */
  export interface TransitionTracingCallbacks {
    onTransitionStart?: (transitionName: string, startTime: number) => void;
    onTransitionProgress?: (
      transitionName: string,
      startTime: number,
      currentTime: number,
      pending: Array<{ name: null | string }>,
    ) => void;
    onTransitionIncomplete?: (
      transitionName: string,
      startTime: number,
      deletions: Array<{ type: string; name?: string | null; endTime: number }>,
    ) => void;
    onTransitionComplete?: (transitionName: string, startTime: number, endTime: number) => void;
    onMarkerProgress?: (
      transitionName: string,
      marker: string,
      startTime: number,
      currentTime: number,
      pending: Array<{ name: null | string }>,
    ) => void;
    onMarkerIncomplete?: (
      transitionName: string,
      marker: string,
      startTime: number,
      deletions: Array<{ type: string; name?: string | null; endTime: number }>,
    ) => void;
    onMarkerComplete?: (
      transitionName: string,
      marker: string,
      startTime: number,
      endTime: number,
    ) => void;
  }

  // ---------------------------------------------------------------------------
  // Host-config type map
  // ---------------------------------------------------------------------------

  /**
   * The renderer-defined type slots that parameterize the whole host config.
   *
   * @remarks
   * The reconciler never inspects these values — they only flow *between your own
   * methods* (what {@link CoreConfig.createInstance} returns is what
   * {@link MutationConfig.appendChild} receives). Every slot defaults to `any`, so
   * you narrow only the ones you use; `interface MyTypes extends HostConfigTypes`
   * with overridden members is legal precisely because the defaults are `any`.
   *
   * Slots for features you don't enable (hydration, resources, view transitions…)
   * can simply stay `any` — they never surface in your code.
   *
   * @example
   * Narrowing the slots a simple mutation-mode renderer cares about:
   * ```typescript
   * interface MyTypes extends HostConfigTypes {
   *   Type: string;
   *   Props: Record<string, unknown>;
   *   Container: MyRootNode;
   *   Instance: MyNode;
   *   TextInstance: MyTextNode;
   *   PublicInstance: MyNode | MyTextNode;
   *   HostContext: null;
   *   TimeoutHandle: ReturnType<typeof setTimeout>;
   *   NoTimeout: -1;
   * }
   * const reconciler = Reconciler<MyTypes>(hostConfig);
   * ```
   */
  export interface HostConfigTypes {
    /** The JSX element type reaching host components (e.g. `'div'`). */
    Type: any;
    /** The props bag of a host element. */
    Props: any;
    /** Whatever you pass as `containerInfo` to {@link Reconciler.createContainer}. */
    Container: any;
    /** A host node produced by {@link CoreConfig.createInstance}. */
    Instance: any;
    /** A host text node produced by {@link CoreConfig.createTextInstance}. */
    TextInstance: any;
    /** Server-rendered `<Activity>` boundary marker (hydration only). */
    ActivityInstance: any;
    /** Server-rendered Suspense boundary marker (hydration only). */
    SuspenseInstance: any;
    /** Union of everything the hydration cursor can point at. */
    HydratableInstance: any;
    /** `useActionState` postback marker (hydration only). */
    FormStateMarkerInstance: any;
    /** What user refs receive — usually the same as `Instance`. */
    PublicInstance: any;
    /** "Where am I in the tree" info threaded through {@link CoreConfig.getChildHostContext}. */
    HostContext: any;
    /** Persistence mode: the pending-children set swapped in at commit. */
    ChildSet: any;
    /** Return type of {@link CoreConfig.scheduleTimeout}. */
    TimeoutHandle: any;
    /** Type of the {@link CoreConfig.noTimeout} sentinel (e.g. `-1`). */
    NoTimeout: any;
    /** Form-status value; {@link CoreConfig.NotPendingTransition} is its idle sentinel. */
    TransitionStatus: any;
    /** A form-like instance handed to {@link CoreConfig.resetFormInstance}. */
    FormInstance: any;
    /**
     * Accumulator created by {@link CoreConfig.startSuspendingCommit} and threaded
     * through every suspensey-commit call. Yours to shape (react-dom uses a
     * counter + pending-resource records).
     */
    SuspendedState: any;
    /** Geometry snapshot produced by {@link ViewTransitionConfig.measureInstance}. */
    InstanceMeasurement: any;
    /** Handle for an in-flight view transition (`{ skipTransition() }`-shaped in DOM). */
    RunningViewTransition: any;
    /** The object exposed via `<ViewTransition ref>`. */
    ViewTransitionInstance: any;
    /** Scroll/pointer timeline driving a gesture transition (experimental). */
    GestureTimeline: any;
    /** The object exposed via `<Fragment ref>`. */
    FragmentInstanceType: any;
    /** Resources: the root resources attach to (DOM: `Document | ShadowRoot`). */
    HoistableRoot: any;
    /** A deduplicated, ref-counted hoistable resource record. */
    Resource: any;
    /** Attached to DevTools internals as `rendererConfig` by {@link Reconciler.injectIntoDevTools}. */
    RendererInspectionConfig: any;
  }

  // ---------------------------------------------------------------------------
  // Host config: core (required for every renderer)
  // ---------------------------------------------------------------------------

  /**
   * The methods and values every renderer must supply, regardless of mode.
   *
   * @remarks
   * Read once at factory time and never validated: a missing member that gets
   * reached is a raw `TypeError`, not a React invariant (the npm build applies no
   * fallback shims). Members marked optional here are genuinely unreachable in
   * current OSS builds unless the corresponding feature/flag is active; everything
   * else is hit by ordinary app behavior — see docs/react-reconciler.md §6 for the
   * omit-X-crashes-at-Y table.
   */
  export interface CoreConfig<T extends HostConfigTypes = HostConfigTypes> {
    // -- mode flags ----------------------------------------------------------

    /**
     * `true` = your tree is imperatively mutable (DOM-like); React drives
     * {@link MutationConfig}. Exactly one of this and {@link CoreConfig.supportsPersistence}
     * must be `true`.
     */
    supportsMutation: boolean;
    /**
     * `true` = your tree is immutable (Fabric-like); React clones changed subtrees
     * during render and swaps them in atomically via {@link PersistenceConfig}.
     */
    supportsPersistence: boolean;
    /** `true` unlocks (and *requires all of*) {@link HydrationConfig}. */
    supportsHydration: boolean;
    /**
     * Selects which of two value slots Context objects use, so two renderers can
     * render concurrently without trampling each other's context values.
     *
     * @remarks
     * Read on every context operation — always provide it. Set `false` when your
     * renderer runs *on top of* another one (e.g. a canvas renderer inside a
     * react-dom app); the host renderer keeps the primary slot.
     */
    isPrimaryRenderer: boolean;
    /**
     * DEV: enable the "update not wrapped in act(...)" warning under test
     * environments. Set `false` if act-semantics make no sense for your platform.
     *
     * @defaultValue effectively `false` when omitted (undefined is falsy)
     */
    warnsIfNotActing?: boolean;

    // -- DevTools identity (read by injectIntoDevTools()) ---------------------

    /** Your renderer's own version string, reported to DevTools (not React's version). */
    rendererVersion?: string;
    /** Your package name as DevTools should display it (e.g. `'react-dom'`). */
    rendererPackageName?: string;
    /** Extra renderer-specific config surfaced to DevTools as `rendererConfig`. */
    extraDevToolsConfig?: T['RendererInspectionConfig'] | null;

    // -- instances (render phase; nodes are detached) -------------------------

    /**
     * Creates a host instance for a mounting host component.
     *
     * @remarks
     * Render (complete) phase. The instance is detached: mutate it freely, but
     * never touch the live tree, never register listeners on parents, and never
     * assume it will mount — concurrent React throws work away routinely. Anything
     * that must happen once the node is really on screen belongs in
     * {@link MutationConfig.commitMount} (opt in by returning `true` from
     * {@link CoreConfig.finalizeInitialChildren}).
     *
     * @param internalHandle - The work-in-progress {@link Fiber}. Store for
     *   instance → fiber lookup if you need it; never read its fields.
     * @returns The new instance. React holds it as the fiber's `stateNode`.
     */
    createInstance(
      type: T['Type'],
      props: T['Props'],
      rootContainer: T['Container'],
      hostContext: T['HostContext'],
      internalHandle: OpaqueHandle,
    ): T['Instance'];

    /**
     * Creates a detached host text node.
     *
     * @remarks
     * Only reached for text children that {@link CoreConfig.shouldSetTextContent}
     * did not absorb. If your platform has no standalone text nodes, make
     * `shouldSetTextContent` always return `true` and throw here.
     */
    createTextInstance(
      text: string,
      rootContainer: T['Container'],
      hostContext: T['HostContext'],
      internalHandle: OpaqueHandle,
    ): T['TextInstance'];

    /**
     * Attaches a child while the parent is **still detached** (render/complete
     * phase, bottom-up tree assembly). The commit-phase counterpart for live
     * parents is {@link MutationConfig.appendChild}.
     */
    appendInitialChild(
      parentInstance: T['Instance'],
      child: T['Instance'] | T['TextInstance'],
    ): void;

    /**
     * Final setup pass for a new instance, after all initial children are attached
     * but before it connects to the screen.
     *
     * @remarks
     * Render (complete) phase — this is where react-dom applies all initial DOM
     * properties. ⚠️ Four arguments: the historical `rootContainer` parameter is gone.
     *
     * @returns `true` to receive a {@link MutationConfig.commitMount} call for this
     *   instance in the layout phase once it's on screen (react-dom: autofocus);
     *   `false` otherwise.
     */
    finalizeInitialChildren(
      instance: T['Instance'],
      type: T['Type'],
      props: T['Props'],
      hostContext: T['HostContext'],
    ): boolean;

    /**
     * Should this element own its text children directly, instead of React
     * creating {@link HostConfigTypes.TextInstance | TextInstance} fibers for them?
     *
     * @remarks
     * Render (begin) phase, every host component — must be pure. Returning `true`
     * means your {@link CoreConfig.createInstance} / {@link MutationConfig.commitUpdate}
     * render `props.children` as text themselves (react-dom does this for
     * `textarea` and single-string children as a fast path). A `true → false`
     * transition across renders triggers {@link MutationConfig.resetTextContent}
     * at the next commit.
     */
    shouldSetTextContent(type: T['Type'], props: T['Props']): boolean;

    /**
     * Maps an instance to what user refs receive. Usually the identity function;
     * return a wrapper if you want refs to see a narrower surface than your
     * internal node type.
     */
    getPublicInstance(instance: T['Instance'] | T['TextInstance']): T['PublicInstance'];

    // -- host context (render phase; must be pure) -----------------------------

    /**
     * The initial {@link HostConfigTypes.HostContext | host context} at the root of
     * the tree. Return `null` if you don't track any.
     */
    getRootHostContext(rootContainer: T['Container']): T['HostContext'] | null;

    /**
     * Derives the context for children of a `type` element (e.g. react-dom switches
     * into SVG namespace under `<svg>`).
     *
     * @remarks
     * Called for every host component; must be pure. ⚠️ Two arguments — the old
     * `rootContainer` parameter is gone. Return `parentHostContext` unchanged when
     * `type` doesn't affect it: the reconciler skips stack pushes on referential
     * equality, so identity is a real optimization here.
     */
    getChildHostContext(parentHostContext: T['HostContext'], type: T['Type']): T['HostContext'];

    // -- commit bracketing -----------------------------------------------------

    /**
     * Start of the before-mutation phase, once per commit with mutation work.
     * Snapshot host state the mutations might clobber (react-dom saves text
     * selection and disables its event system).
     *
     * @returns Return `null`. (The return value only feeds the
     *   `enableCreateEventHandleAPI` focus-tracking path, off in OSS builds.)
     */
    prepareForCommit(containerInfo: T['Container']): object | null;

    /**
     * End of the mutation phase, before layout effects run. Restore what
     * {@link CoreConfig.prepareForCommit} saved — and a natural place to flush a
     * batched paint if your renderer draws explicitly.
     */
    resetAfterCommit(containerInfo: T['Container']): void;

    /**
     * Wipe all existing children out of the container.
     *
     * @remarks
     * Before-mutation phase, on the root's *first client-rendered commit* only
     * (and after abandoned hydration) — clears whatever markup occupied the
     * container before React took ownership.
     */
    clearContainer(container: T['Container']): void;

    /**
     * A container is about to be used as a portal target (portal's first mount,
     * render phase). react-dom attaches its delegated event listeners here; a
     * no-op is fine, but the method must exist if apps use portals.
     */
    preparePortalMount(portalContainer: T['Container']): void;

    /**
     * Passive phase, called for **every** deleted host instance after commit.
     * Sever renderer-internal pointers (react-dom deletes its fiber expandos to
     * prevent leaks). No-op is fine; deletions reach it unconditionally.
     */
    detachDeletedInstance(node: T['Instance']): void;

    // -- timers ----------------------------------------------------------------

    /**
     * `setTimeout` equivalent. Used to delay committing a Suspense fallback,
     * giving suspended data a beat to arrive before the UI regresses.
     */
    scheduleTimeout(fn: (...args: unknown[]) => unknown, delay?: number): T['TimeoutHandle'];
    /** `clearTimeout` equivalent — cancels a {@link CoreConfig.scheduleTimeout}. */
    cancelTimeout(handle: T['TimeoutHandle']): void;
    /**
     * A sentinel {@link CoreConfig.scheduleTimeout} can never return (e.g. `-1`).
     *
     * @remarks
     * Read inside the FiberRoot constructor — omitting it crashes
     * {@link Reconciler.createContainer} itself, before anything renders.
     */
    noTimeout: T['NoTimeout'];

    // -- update priority (replaces getCurrentEventPriority) --------------------

    /**
     * Store `newPriority` in renderer-owned state, synchronously.
     *
     * @remarks
     * The priority slot lives in *your* module (not the reconciler's) so your
     * event system and React share one source of truth — react-dom keeps it on a
     * shared-internals object so multiple react-dom copies agree. The reconciler
     * brackets every commit, `flushSync`, and `startTransition` scope with
     * save/override/restore pairs of this and {@link CoreConfig.getCurrentUpdatePriority},
     * so both must be plain, synchronous accessors.
     */
    setCurrentUpdatePriority(newPriority: EventPriority): void;

    /** Return exactly what {@link CoreConfig.setCurrentUpdatePriority} last stored. */
    getCurrentUpdatePriority(): EventPriority;

    /**
     * Resolve the priority for an update that arrives with no explicit context —
     * called for **every** `setState`/`root.render()` outside a transition.
     *
     * @remarks
     * The contract, in order: return the stored priority if one is set; otherwise
     * the priority of the host event currently being dispatched (react-dom
     * inspects `window.event`: click/keydown → discrete, mousemove/scroll →
     * continuous); otherwise `DefaultEventPriority`. Never return `NoEventPriority`.
     *
     * This trio replaces the removed `getCurrentEventPriority()`.
     *
     * @example
     * The canonical implementation (mirrors the in-repo noop renderer):
     * ```typescript
     * import { DefaultEventPriority, NoEventPriority } from 'react-reconciler/constants';
     * import type { EventPriority } from 'react-reconciler';
     *
     * let currentUpdatePriority: EventPriority = NoEventPriority;
     *
     * const priorityConfig = {
     *   setCurrentUpdatePriority(p: EventPriority) { currentUpdatePriority = p; },
     *   getCurrentUpdatePriority: () => currentUpdatePriority,
     *   resolveUpdatePriority(): EventPriority {
     *     if (currentUpdatePriority !== NoEventPriority) return currentUpdatePriority;
     *     return DefaultEventPriority; // or derive from your in-flight host event
     *   },
     * };
     * ```
     */
    resolveUpdatePriority(): EventPriority;

    /**
     * A transition was scheduled during the current host event — should it render
     * synchronously before yielding?
     *
     * @remarks
     * Reached by any `startTransition` fired inside one of your events. react-dom
     * returns `true` exactly once per `popstate` so back/forward navigation paints
     * scroll-correct content immediately. Unless you have such a case:
     * `() => false`.
     */
    shouldAttemptEagerTransition(): boolean;

    // -- suspensey commits (reached by ANY transition/retry commit) ------------

    /**
     * Render phase, on mount: might committing this instance ever need to wait on
     * the host environment (image decode, font load…)? Must be pure — `true` only
     * flags the fiber; the actual waiting is negotiated later via
     * {@link CoreConfig.preloadInstance} and {@link CoreConfig.suspendInstance}.
     *
     * @remarks
     * ⚠️ This family is *not* exotic: `enableViewTransition` defaults on, which
     * routes every transition/retry/idle-lane commit through the suspensey path.
     * Renderers with nothing to wait for still need the trivial implementations
     * (see docs/react-reconciler.md §5.5).
     */
    maySuspendCommit(type: T['Type'], props: T['Props']): boolean;
    /** Update-time variant of {@link CoreConfig.maySuspendCommit} (react-dom: did `src` change?). */
    maySuspendCommitOnUpdate(
      type: T['Type'],
      oldProps: T['Props'],
      newProps: T['Props'],
    ): boolean;
    /** May this instance suspend even a *synchronous* commit? Almost always `() => false`. */
    maySuspendCommitInSyncRender(type: T['Type'], props: T['Props']): boolean;

    /**
     * Start loading whatever the instance needs to commit — render phase, as early
     * as possible, to shorten the eventual wait.
     *
     * @remarks
     * ⚠️ `instance` is the **first** parameter now (older docs show `(type, props)`).
     *
     * @returns Whether the instance is already ready (react-dom: `img.complete`).
     *   `false` lets React keep rendering siblings and suspend the *commit*
     *   instead of the render.
     */
    preloadInstance(instance: T['Instance'], type: T['Type'], props: T['Props']): boolean;

    /**
     * Pre-commit: create the accumulator that the subsequent
     * {@link CoreConfig.suspendInstance} / {@link CoreConfig.waitForCommitToBeReady}
     * calls thread through.
     *
     * @remarks
     * ⚠️ Returns the state explicitly now — the old module-level-accumulation form
     * (`(): void`) is gone. Shape it however you like; `null` works for renderers
     * that never wait.
     */
    startSuspendingCommit(): T['SuspendedState'];

    /** Pre-commit, once per flagged instance: register its pending work with `state`. */
    suspendInstance(
      state: T['SuspendedState'],
      instance: T['Instance'],
      type: T['Type'],
      props: T['Props'],
    ): void;

    /**
     * Pre-commit: if a previous view transition is still animating, register a wait
     * on it so the new commit doesn't tear it. No-op when not applicable.
     */
    suspendOnActiveViewTransition(state: T['SuspendedState'], rootContainer: T['Container']): void;

    /**
     * The decision point: can this commit proceed now?
     *
     * @remarks
     * Return `null` to commit immediately. Otherwise return a *subscribe* function:
     * React calls it with the real commit continuation; invoke that continuation
     * when everything registered in `state` is ready (or your timeout expires), and
     * return a *cancel* function React stores as `root.cancelPendingCommit` (called
     * if newer work supersedes this commit). react-dom waits ≤60s for stylesheets
     * and ≤800ms for images here.
     *
     * @param timeoutOffset - Negative ms adjustment: how long React has already
     *   been waiting on this content, so your timeout budget shrinks accordingly.
     *
     * @example
     * A counting implementation for a renderer that tracks pending loads in `state`:
     * ```typescript
     * interface Suspended { count: number; commit: null | (() => void) }
     *
     * function waitForCommitToBeReady(
     *   state: Suspended | null,
     *   timeoutOffset: number,
     * ): null | ((commit: () => void) => () => void) {
     *   if (state === null || state.count === 0) return null; // nothing pending
     *   return (commit) => {
     *     state.commit = commit;               // called by your load handlers
     *     const timer = setTimeout(commit, 500 + timeoutOffset);
     *     return () => {                        // cancel: newer work superseded us
     *       state.commit = null;
     *       clearTimeout(timer);
     *     };
     *   };
     * }
     * ```
     */
    waitForCommitToBeReady(
      state: T['SuspendedState'],
      timeoutOffset: number,
    ): null | ((initiateCommit: () => void) => () => void);

    /**
     * Profiling builds only: a human-readable reason for the performance track
     * (react-dom: `'Suspended on CSS'`), or `null`.
     */
    getSuspendedCommitReason(state: T['SuspendedState'], rootContainer: T['Container']): null | string;

    // -- forms / transition status ---------------------------------------------

    /**
     * The "no transition pending" sentinel of your
     * {@link HostConfigTypes.TransitionStatus | TransitionStatus} — what
     * `useFormStatus` reads when no form action is in flight. Also initialize
     * {@link CoreConfig.HostTransitionContext}'s value slots to this.
     */
    NotPendingTransition: T['TransitionStatus'];
    /**
     * The hand-built context object backing `useFormStatus` — see
     * {@link HostTransitionContext} for the required shape and an example.
     * Only dereferenced when a form transition actually occurs.
     */
    HostTransitionContext: HostTransitionContext<T['TransitionStatus']>;
    /**
     * Mutation phase, `FormReset` flag: a completed form action requested a reset —
     * clear the form's uncontrolled state (react-dom calls `form.reset()`).
     * No-op if your platform has nothing form-like.
     */
    resetFormInstance(form: T['FormInstance']): void;

    // -- profiling hooks (live in dev builds: __PROFILE__ = true) ---------------

    /**
     * Snapshot the current host event so the profiler can tell scheduler ticks
     * apart from real user events. No-op is fine.
     *
     * @remarks
     * This trio is gated on profiling flags — but npm **dev builds compile with
     * `__PROFILE__ = true`**, so they run in development for third-party renderers
     * too. Provide the stubs or dev crashes.
     */
    trackSchedulerEvent(): void;
    /** Type of the host event that caused the current work, for profiler attribution; or `null`. */
    resolveEventType(): null | string;
    /** Timestamp of that event; `-1.1` is the "no event" sentinel. */
    resolveEventTimeStamp(): number;

    // -- rarely needed (flag-gated or feature-specific; no-ops suffice) ---------

    /** Reverse node → fiber lookup. Only test selectors / scope API call it. */
    getInstanceFromNode?(node: any): OpaqueHandle | null;
    /** `enableCreateEventHandleAPI` (off in OSS): focused subtree about to hide/unmount. */
    beforeActiveInstanceBlur?(internalHandle: OpaqueHandle): void;
    /** `enableCreateEventHandleAPI` (off in OSS): pairs with {@link CoreConfig.beforeActiveInstanceBlur}. */
    afterActiveInstanceBlur?(): void;
    /** `enableScopeAPI` (off in OSS, www-only). */
    prepareScopeUpdate?(scopeInstance: any, internalHandle: OpaqueHandle): void;
    /** `enableScopeAPI` (off in OSS, www-only). */
    getInstanceFromScope?(scopeInstance: any): OpaqueHandle | null;
    /** Transition Tracing only (off in OSS). react-dom: double `requestAnimationFrame`. */
    requestPostPaintCallback?(callback: (time: number) => void): void;
    /**
     * DEV: return a **pre-bound** console call — binding (rather than wrapping)
     * preserves click-through-to-source in devtools. Used to replay logs/errors
     * that originated elsewhere (React Server Components) with a badge.
     *
     * @example
     * Minimal badge-less implementation:
     * ```typescript
     * const bindToConsole = (methodName: string, args: ReadonlyArray<unknown>) =>
     *   Function.prototype.bind.apply(
     *     (console as unknown as Record<string, (...a: unknown[]) => unknown>)[methodName],
     *     [console, ...args],
     *   );
     * ```
     */
    bindToConsole?(
      methodName: string,
      args: ReadonlyArray<any>,
      badgeName: string,
    ): (...args: unknown[]) => unknown;

    // -- microtasks --------------------------------------------------------------

    /**
     * `true` lets the reconciler process its root schedule in a microtask, so sync
     * updates scheduled during one of your events flush at the end of that event —
     * before paint. Without it, the same work runs as an immediate Scheduler task
     * and batching boundaries get coarser. Recommended `true` unless your platform
     * has a better end-of-event hook (React Native opts out).
     */
    supportsMicrotasks?: boolean;
    /** `queueMicrotask` equivalent; required if {@link CoreConfig.supportsMicrotasks}. */
    scheduleMicrotask?(fn: () => void): void;

    // -- gesture clones (enableGestureTransition, experimental channel only) ------

    /**
     * Clone a committed instance for the gesture-transition parallel tree
     * (experimental channel only; safe to omit or throw on stable).
     *
     * @param keepChildren - `true` = deep clone (subtree unchanged); `false` =
     *   shallow clone, React repopulates children itself.
     */
    cloneMutableInstance?(instance: T['Instance'], keepChildren: boolean): T['Instance'];
    /** Text-node sibling of {@link CoreConfig.cloneMutableInstance}. */
    cloneMutableTextInstance?(textInstance: T['TextInstance']): T['TextInstance'];
  }

  // ---------------------------------------------------------------------------
  // Host config: mutation mode
  // ---------------------------------------------------------------------------

  /**
   * Commit-phase methods for renderers that mutate their tree in place
   * ({@link CoreConfig.supportsMutation | supportsMutation: true}).
   *
   * @remarks
   * All run in the mutation phase unless noted, each wrapped in try/catch that
   * routes failures to the nearest error boundary. How React picks the
   * container-vs-instance variant of the structural methods: at commit it walks up
   * to the nearest *host* parent fiber — a host component gets the instance
   * variant, the root or a portal gets the `…Container` variant.
   */
  export interface MutationConfig<T extends HostConfigTypes = HostConfigTypes> {
    supportsMutation: true;

    // structure (mutation phase)

    /** Append to a live parent instance (no following host sibling exists). */
    appendChild(parentInstance: T['Instance'], child: T['Instance'] | T['TextInstance']): void;
    /** {@link MutationConfig.appendChild} when the host parent is the root/portal container. */
    appendChildToContainer(
      container: T['Container'],
      child: T['Instance'] | T['TextInstance'],
    ): void;
    /**
     * Insert `child` before `beforeChild` — used for **both** insertion and
     * reordering, exactly like DOM `insertBefore` (repositioning an existing child
     * must work). In hydrating renderers `beforeChild` may be a Suspense/Activity
     * marker instance.
     */
    insertBefore(
      parentInstance: T['Instance'],
      child: T['Instance'] | T['TextInstance'],
      beforeChild: T['Instance'] | T['TextInstance'] | T['SuspenseInstance'] | T['ActivityInstance'],
    ): void;
    /** {@link MutationConfig.insertBefore} for root/portal containers. */
    insertInContainerBefore(
      container: T['Container'],
      child: T['Instance'] | T['TextInstance'],
      beforeChild: T['Instance'] | T['TextInstance'] | T['SuspenseInstance'] | T['ActivityInstance'],
    ): void;
    /**
     * Remove a child from a live parent.
     *
     * @remarks
     * Called **only for the topmost deleted node** of a removed subtree —
     * descendants are unmounted logically and left to your platform's GC. Don't
     * traverse; anything needing per-node cleanup belongs in
     * {@link CoreConfig.detachDeletedInstance}, which does fire for every node.
     */
    removeChild(
      parentInstance: T['Instance'],
      child: T['Instance'] | T['TextInstance'] | T['SuspenseInstance'] | T['ActivityInstance'],
    ): void;
    /** {@link MutationConfig.removeChild} for root/portal containers. */
    removeChildFromContainer(
      container: T['Container'],
      child: T['Instance'] | T['TextInstance'] | T['SuspenseInstance'] | T['ActivityInstance'],
    ): void;

    // updates

    /**
     * Apply a prop change to a live instance — **the diffing is yours**.
     *
     * @remarks
     * The old `prepareUpdate`/`updatePayload` pipeline is gone. React sets the
     * `Update` flag whenever `prevProps !== nextProps` (referential!), so this is
     * called for every re-render of a host component whose props object changed at
     * all; compare and apply the delta yourself. During hydration reuse it's
     * called with `prevProps === nextProps` — a cheap early-out is worthwhile.
     *
     * @example
     * ```typescript
     * function commitUpdate(
     *   instance: { props: Record<string, unknown> },
     *   type: string,
     *   prevProps: Record<string, unknown>,
     *   nextProps: Record<string, unknown>,
     * ): void {
     *   if (prevProps === nextProps) return;   // hydration reuse
     *   for (const key of Object.keys(nextProps)) {
     *     if (prevProps[key] !== nextProps[key]) instance.props[key] = nextProps[key];
     *   }
     *   for (const key of Object.keys(prevProps)) {
     *     if (!(key in nextProps)) delete instance.props[key];
     *   }
     * }
     * ```
     */
    commitUpdate(
      instance: T['Instance'],
      type: T['Type'],
      prevProps: T['Props'],
      nextProps: T['Props'],
      internalHandle: OpaqueHandle,
    ): void;
    /** Replace a text node's content (`Update` flag set when `oldText !== newText`). */
    commitTextUpdate(textInstance: T['TextInstance'], oldText: string, newText: string): void;
    /**
     * **Layout phase**, mount only, and only for instances whose
     * {@link CoreConfig.finalizeInitialChildren} returned `true` — the instance is
     * now attached and visible (react-dom: trigger `autoFocus`). Also re-fires when
     * hidden `<Activity>`/Offscreen content reappears. Never fires on updates.
     */
    commitMount(
      instance: T['Instance'],
      type: T['Type'],
      props: T['Props'],
      internalHandle: OpaqueHandle,
    ): void;
    /**
     * Clear text you rendered via {@link CoreConfig.shouldSetTextContent} after the
     * element stops owning its text (`ContentReset` flag). Leave empty if you never
     * return `true` from `shouldSetTextContent`.
     */
    resetTextContent(instance: T['Instance']): void;

    // visibility (Suspense / <Activity> / Offscreen)

    /**
     * Make an instance invisible **without removing it** — Suspense re-suspending
     * over mounted content, or `<Activity mode="hidden">` (react-dom:
     * `display: none !important`). React hides only the topmost host nodes of the
     * hidden subtree; descendants inherit.
     */
    hideInstance(instance: T['Instance']): void;
    /** Text sibling of {@link MutationConfig.hideInstance} (react-dom: `nodeValue = ''`). */
    hideTextInstance(textInstance: T['TextInstance']): void;
    /**
     * Undo {@link MutationConfig.hideInstance}. `props` is supplied so you restore
     * the *prop-specified* visual state (react-dom restores `props.style.display`,
     * not just "visible").
     */
    unhideInstance(instance: T['Instance'], props: T['Props']): void;
    /** Undo {@link MutationConfig.hideTextInstance}, restoring `text`. */
    unhideTextInstance(textInstance: T['TextInstance'], text: string): void;
  }

  // ---------------------------------------------------------------------------
  // Host config: persistence mode
  // ---------------------------------------------------------------------------

  /**
   * Methods for renderers over immutable trees
   * ({@link CoreConfig.supportsPersistence | supportsPersistence: true}) — the
   * React Native Fabric model.
   *
   * @remarks
   * Committed instances are never mutated. During the **render (complete) phase**
   * React clones the spine of whatever changed ({@link PersistenceConfig.cloneInstance}),
   * re-attaching children via {@link CoreConfig.appendInitialChild}, and assembles a
   * fresh {@link HostConfigTypes.ChildSet | ChildSet} for the root/portal. The only
   * commit-phase mutation is one atomic swap:
   * {@link PersistenceConfig.replaceContainerChildren}. Hiding under
   * Suspense/`<Activity>` likewise clones-with-hidden-styling instead of mutating.
   */
  export interface PersistenceConfig<T extends HostConfigTypes = HostConfigTypes> {
    supportsPersistence: true;

    /**
     * Clone an instance whose subtree changed — render (complete) phase.
     *
     * @remarks
     * ⚠️ The current **6-argument form**: no `updatePayload`, no `recyclableInstance`.
     * Returning the *same* instance signals "nothing changed here" and React reuses
     * it without marking a clone.
     *
     * @param keepChildren - `true` = the child list is unchanged, carry it over;
     *   `false` = React will re-append children to the clone itself.
     * @param newChildSet - Only ever non-null under the
     *   `passChildrenWhenCloningPersistedNodes` flag (off in all public builds) —
     *   in practice, expect `undefined` and ignore it.
     */
    cloneInstance(
      instance: T['Instance'],
      type: T['Type'],
      oldProps: T['Props'],
      newProps: T['Props'],
      keepChildren: boolean,
      newChildSet?: T['ChildSet'] | null,
    ): T['Instance'];
    /** Fresh, empty child set for a root/portal (render phase). Fabric: an array or opaque node set. */
    createContainerChildSet(): T['ChildSet'];
    /** Add one top-level host node to the pending set (render phase, in order). */
    appendChildToContainerChildSet(
      childSet: T['ChildSet'],
      child: T['Instance'] | T['TextInstance'],
    ): void;
    /** Render phase, after the set is complete — last pre-commit finalization hook. */
    finalizeContainerChildren(container: T['Container'], newChildren: T['ChildSet']): void;
    /**
     * Commit (mutation) phase: **the atomic swap** — make `newChildren` the
     * container's children (Fabric: `completeRoot`). Also called with a fresh empty
     * set when a portal is deleted.
     */
    replaceContainerChildren(container: T['Container'], newChildren: T['ChildSet']): void;
    /** Persistence's {@link MutationConfig.hideInstance}: clone with hidden styling applied. */
    cloneHiddenInstance(
      instance: T['Instance'],
      type: T['Type'],
      props: T['Props'],
    ): T['Instance'];
    /** Text sibling of {@link PersistenceConfig.cloneHiddenInstance}. */
    cloneHiddenTextInstance(instance: T['Instance'], text: string): T['TextInstance'];
  }

  // ---------------------------------------------------------------------------
  // Host config: hydration
  // ---------------------------------------------------------------------------

  /**
   * Methods to attach the initial client render to server-generated host nodes
   * instead of creating them ({@link CoreConfig.supportsHydration | supportsHydration: true}).
   *
   * @remarks
   * **All members are required once you opt in** — including the `<Activity>`
   * methods, which are unconditional in current builds.
   *
   * The mental model is a **cursor walk**: the reconciler tracks "the next
   * {@link HostConfigTypes.HydratableInstance | hydratable node} I expect".
   * During the *begin* phase each host component/text/boundary tries to **claim**
   * the node under the cursor (`canHydrate*` — return the typed instance to
   * accept, `null` to reject); a claim descends via `getFirstHydratableChild*`, a
   * rejection throws internally and client-renders that boundary. During the
   * *complete* phase the cursor pops back up (`getNextHydratableSibling*`) and the
   * `hydrate*` methods attach props/fibers to the claimed nodes. Suspense and
   * `<Activity>` interiors are *skipped* on the first pass — their marker
   * instances are stored as "dehydrated" state and hydrated lazily later
   * (selective hydration). Finally, the commit-phase `commitHydrated*` methods
   * fire so you can replay events that were queued against not-yet-hydrated
   * targets.
   *
   * Methods below carry one line each on what makes them distinct; phases and the
   * full walk are described here and in docs/react-reconciler.md §5.9.
   */
  export interface HydrationConfig<T extends HostConfigTypes = HostConfigTypes> {
    supportsHydration: true;

    // claiming (begin phase; pure)

    /**
     * Try to claim a node for a host component. Return the typed instance to
     * accept, `null` to reject. When `inRootOrSingleton` is true you may *skip
     * past* foreign nodes (react-dom tolerates extension-injected junk at the
     * root) by returning a later matching sibling.
     */
    canHydrateInstance(
      instance: T['HydratableInstance'],
      type: T['Type'],
      props: T['Props'],
      inRootOrSingleton: boolean,
    ): null | T['Instance'];
    /** Claim a text node; react-dom rejects empty strings (never emitted by HTML). */
    canHydrateTextInstance(
      instance: T['HydratableInstance'],
      text: string,
      inRootOrSingleton: boolean,
    ): null | T['TextInstance'];
    /** Claim an `<Activity>` boundary marker. */
    canHydrateActivityInstance(
      instance: T['HydratableInstance'],
      inRootOrSingleton: boolean,
    ): null | T['ActivityInstance'];
    /** Claim a Suspense boundary marker. */
    canHydrateSuspenseInstance(
      instance: T['HydratableInstance'],
      inRootOrSingleton: boolean,
    ): null | T['SuspenseInstance'];

    // cursor movement (pure)

    /** Descend: first hydratable node inside a claimed instance. */
    getFirstHydratableChild(parentInstance: T['Instance']): null | T['HydratableInstance'];
    /** Cursor seed: first hydratable node in the root container. */
    getFirstHydratableChildWithinContainer(
      container: T['Container'],
    ): null | T['HydratableInstance'];
    /** Re-entry point when a dehydrated `<Activity>` boundary hydrates later. */
    getFirstHydratableChildWithinActivityInstance(
      parentInstance: T['ActivityInstance'],
    ): null | T['HydratableInstance'];
    /** Re-entry point when a dehydrated Suspense boundary hydrates later. */
    getFirstHydratableChildWithinSuspenseInstance(
      parentInstance: T['SuspenseInstance'],
    ): null | T['HydratableInstance'];
    /** Advance: next hydratable sibling, skipping non-hydratable noise. */
    getNextHydratableSibling(
      instance: T['HydratableInstance'],
    ): null | T['HydratableInstance'];
    /** Skip a whole (possibly nested) `<Activity>` boundary without entering it. */
    getNextHydratableInstanceAfterActivityInstance(
      activityInstance: T['ActivityInstance'],
    ): null | T['HydratableInstance'];
    /** Skip a whole (possibly nested) Suspense boundary without entering it. */
    getNextHydratableInstanceAfterSuspenseInstance(
      suspenseInstance: T['SuspenseInstance'],
    ): null | T['HydratableInstance'];

    // singleton interop (only with supportsSingletons)

    /** Descend into a singleton *scope* (react-dom: `<head>`), stashing the outer cursor. */
    getFirstHydratableChildWithinSingleton?(
      type: T['Type'],
      singletonInstance: T['Instance'],
      currentHydratableInstance: null | T['HydratableInstance'],
    ): null | T['HydratableInstance'];
    /** Restore the stashed cursor when the singleton scope pops. */
    getNextHydratableSiblingAfterSingleton?(
      type: T['Type'],
      currentHydratableInstance: null | T['HydratableInstance'],
    ): null | T['HydratableInstance'];

    // attaching (complete phase)

    /**
     * Attach fiber + props to a claimed instance.
     * @returns `false` signals a mismatch → the boundary client-renders.
     */
    hydrateInstance(
      instance: T['Instance'],
      type: T['Type'],
      props: T['Props'],
      hostContext: T['HostContext'],
      internalHandle: OpaqueHandle,
    ): boolean;
    /**
     * Attach a claimed text node; `parentProps` is the parent host component's
     * props (react-dom checks `suppressHydrationWarning` on it).
     */
    hydrateTextInstance(
      textInstance: T['TextInstance'],
      text: string,
      internalHandle: OpaqueHandle,
      parentProps: null | T['Props'],
    ): boolean;
    /** Attach the fiber to a claimed `<Activity>` marker (no mismatch possible). */
    hydrateActivityInstance(
      activityInstance: T['ActivityInstance'],
      internalHandle: OpaqueHandle,
    ): void;
    /** Attach the fiber to a claimed Suspense marker. */
    hydrateSuspenseInstance(
      suspenseInstance: T['SuspenseInstance'],
      internalHandle: OpaqueHandle,
    ): void;

    // dehydrated Suspense boundary state

    /** Is the server still streaming this boundary's content? (react-dom: `<!--$?-->`/`<!--$~-->`.) */
    isSuspenseInstancePending(instance: T['SuspenseInstance']): boolean;
    /** Did the server give up and render the fallback? (`<!--$!-->` — client must render content.) */
    isSuspenseInstanceFallback(instance: T['SuspenseInstance']): boolean;
    /** Error details the server embedded alongside a fallback boundary. */
    getSuspenseInstanceFallbackErrorDetails(instance: T['SuspenseInstance']): {
      digest: string | null | undefined;
      message?: string;
      stack?: string;
      componentStack?: string;
    };
    /**
     * Register `callback` to fire when the server content for a pending boundary
     * later arrives — the streaming-SSR runtime hook (react-dom wires
     * `instance._reactRetry` for Fizz).
     */
    registerSuspenseInstanceRetry(instance: T['SuspenseInstance'], callback: () => void): void;

    // boundary teardown & visibility (commit phase)

    /** Delete a dehydrated boundary's server markup, start marker through end marker (nesting-aware). */
    clearSuspenseBoundary(
      parentInstance: T['Instance'],
      suspenseInstance: T['SuspenseInstance'],
    ): void;
    /** {@link HydrationConfig.clearSuspenseBoundary} when the host parent is the container. */
    clearSuspenseBoundaryFromContainer(
      container: T['Container'],
      suspenseInstance: T['SuspenseInstance'],
    ): void;
    /**
     * Reserved: currently has **zero reconciler call sites** — dehydrated
     * `<Activity>` deletion flows through {@link HydrationConfig.clearSuspenseBoundary}.
     * Provide it anyway; the surface declares it.
     */
    clearActivityBoundary(
      parentInstance: T['Instance'],
      activityInstance: T['ActivityInstance'],
    ): void;
    /** Reserved, container variant of {@link HydrationConfig.clearActivityBoundary}. */
    clearActivityBoundaryFromContainer(
      container: T['Container'],
      activityInstance: T['ActivityInstance'],
    ): void;
    /** Hide a still-dehydrated boundary's markup (Offscreen toggling before hydration). */
    hideDehydratedBoundary(instance: T['SuspenseInstance'] | T['ActivityInstance']): void;
    /** Undo {@link HydrationConfig.hideDehydratedBoundary}. */
    unhideDehydratedBoundary(instance: T['SuspenseInstance'] | T['ActivityInstance']): void;

    // commit-time notifications (event replay)

    /** Fires only for instances where {@link HydrationConfig.finalizeHydratedChildren} returned `true`. */
    commitHydratedInstance(
      instance: T['Instance'],
      type: T['Type'],
      props: T['Props'],
      internalHandle: OpaqueHandle,
    ): void;
    /** The root finished hydrating — replay events queued against it. */
    commitHydratedContainer(container: T['Container']): void;
    /** An `<Activity>` boundary finished hydrating — replay its queued events. */
    commitHydratedActivityInstance(activityInstance: T['ActivityInstance']): void;
    /** A Suspense boundary finished hydrating — replay its queued events. */
    commitHydratedSuspenseInstance(suspenseInstance: T['SuspenseInstance']): void;
    /**
     * Complete phase: return `true` to request a
     * {@link HydrationConfig.commitHydratedInstance} for this instance at commit.
     * Return `false` unless you need commit-time work per hydrated instance
     * (react-dom only uses it behind an experimental flag).
     */
    finalizeHydratedChildren(
      instance: T['Instance'],
      type: T['Type'],
      props: T['Props'],
      hostContext: T['HostContext'],
    ): boolean;
    /** End of **every** commit while hydration is supported: flush replayed events. No-op OK. */
    flushHydrationEvents(): void;

    // mismatch handling & DEV diagnostics

    /**
     * Server rendered more children than the client claims: delete-and-warn
     * (`true`) or tolerate the tail (`false` — react-dom tolerates inside
     * `form`/`button`, where browsers and extensions inject nodes).
     */
    shouldDeleteUnhydratedTailInstances(parentType: T['Type']): boolean;
    /**
     * DEV nesting validation before a claim; the boolean only suppresses duplicate
     * warnings, never changes behavior. Return `true` in prod.
     */
    validateHydratableInstance(
      type: T['Type'],
      props: T['Props'],
      hostContext: T['HostContext'],
    ): boolean;
    /** DEV text-nesting validation; same contract as {@link HydrationConfig.validateHydratableInstance}. */
    validateHydratableTextInstance(text: string, hostContext: T['HostContext']): boolean;
    /** DEV-only: server-vs-client prop diff for the mismatch report; `null` in prod is fine. */
    diffHydratedPropsForDevWarnings(
      instance: T['Instance'],
      type: T['Type'],
      props: T['Props'],
      hostContext: T['HostContext'],
    ): null | T['Props'];
    /** DEV-only: the server's text if it differs from the client's, else `null`. */
    diffHydratedTextForDevWarnings(
      textInstance: T['TextInstance'],
      text: string,
      parentProps: null | T['Props'],
    ): null | string;
    /** DEV-only: describe an unclaimed node for the "extra nodes" warning. */
    describeHydratableInstanceForDevWarnings(
      instance: T['HydratableInstance'],
    ): string | { type: T['Type']; props: T['Props'] };

    // form-state markers (useActionState postbacks)

    /** Claim a form-state marker (react-dom: `<!--F!-->` / `<!--F-->` comments). */
    canHydrateFormStateMarker(
      instance: T['HydratableInstance'],
      inRootOrSingleton: boolean,
    ): null | T['FormStateMarkerInstance'];
    /** Does the postback form state passed to `hydrateRoot` apply to this hook instance? */
    isFormStateMarkerMatching(markerInstance: T['FormStateMarkerInstance']): boolean;
  }

  // ---------------------------------------------------------------------------
  // Host config: resources (hoistables) — supportsResources
  // ---------------------------------------------------------------------------

  /**
   * react-dom's "Float" model: elements rendered anywhere in the tree that must
   * live at the document level (`<link>`, `<style>`, async `<script>`, `<title>`,
   * `<meta>`). Opting in (`supportsResources: true`) makes
   * {@link ResourcesConfig.isHostHoistableType} run during fiber creation, tagging
   * matching elements as HostHoistable fibers.
   *
   * @remarks
   * A hoistable resolves per render to either a **Resource** (deduplicated,
   * ref-counted singleton — {@link ResourcesConfig.getResource} returns non-null)
   * or a **hoistable instance** (owned 1:1 by its fiber but still moved to the
   * root). Resources have no reconciler-managed children. Almost certainly
   * DOM-specific — skip this family unless your host has a "document head" analog.
   */
  export interface ResourcesConfig<T extends HostConfigTypes = HostConfigTypes> {
    supportsResources: true;

    /** Render phase, during fiber creation — is this element hoistable at all? Must be pure. */
    isHostHoistableType(
      type: T['Type'],
      props: T['Props'],
      hostContext: T['HostContext'],
    ): boolean;
    /** Resolve the root that hoisted content attaches to (DOM: `getRootNode()`). */
    getHoistableRoot(container: T['Container']): T['HoistableRoot'];
    /**
     * Render-phase classification: return the deduplicated {@link HostConfigTypes.Resource},
     * or `null` meaning "plain hoistable instance path". May kick off preloads.
     */
    getResource(
      type: T['Type'],
      currentProps: T['Props'],
      pendingProps: T['Props'],
      currentResource: null | T['Resource'],
    ): null | T['Resource'];
    /** Render phase: create (but don't insert) a 1:1 hoistable instance. */
    createHoistableInstance(
      type: T['Type'],
      props: T['Props'],
      rootContainer: T['Container'],
      internalHandle: OpaqueHandle,
    ): T['Instance'];
    /** Commit: insert a hoistable instance at the root (react-dom: into `<head>`). */
    mountHoistable(
      hoistableRoot: T['HoistableRoot'],
      type: T['Type'],
      instance: T['Instance'],
    ): void;
    /** Commit: remove a hoistable instance from the root. */
    unmountHoistable(instance: T['Instance']): void;
    /** Commit: adopt the matching server-rendered head tag instead of creating one. */
    hydrateHoistable(
      hoistableRoot: T['HoistableRoot'],
      type: T['Type'],
      props: T['Props'],
      internalHandle: OpaqueHandle,
    ): T['Instance'];
    /** Commit: ref-count++ — first acquire creates/inserts (stylesheets by precedence). */
    acquireResource(
      hoistableRoot: T['HoistableRoot'],
      resource: T['Resource'],
      props: T['Props'],
    ): null | T['Instance'];
    /** Commit: ref-count-- (react-dom does not eagerly remove the node). */
    releaseResource(resource: T['Resource']): void;
    /** Start of the mutation pass: clear per-commit hydration caches. */
    prepareToCommitHoistables(): void;

    // suspensey-commit twins for resources (see CoreConfig.maySuspendCommit family)

    /** {@link CoreConfig.maySuspendCommit} for resources (react-dom: not-yet-inserted stylesheets). */
    mayResourceSuspendCommit(resource: T['Resource']): boolean;
    /** {@link CoreConfig.preloadInstance} for resources; `false` = suspend the commit. */
    preloadResource(resource: T['Resource']): boolean;
    /** {@link CoreConfig.suspendInstance} for resources: register the pending load with `state`. */
    suspendResource(
      state: T['SuspendedState'],
      hoistableRoot: T['HoistableRoot'],
      resource: T['Resource'],
      props: T['Props'],
    ): void;
  }

  // ---------------------------------------------------------------------------
  // Host config: singletons — supportsSingletons
  // ---------------------------------------------------------------------------

  /**
   * Elements that exist exactly once per document and must be **adopted, not
   * created or destroyed** (react-dom: `<html>`, `<head>`, `<body>`). Opting in
   * (`supportsSingletons: true`) makes matching elements HostSingleton fibers:
   * React resolves the pre-existing node during render, "acquires" it at commit,
   * and "releases" (never removes) it on unmount.
   */
  export interface SingletonsConfig<T extends HostConfigTypes = HostConfigTypes> {
    supportsSingletons: true;

    /** Render phase, fiber creation — is `type` a singleton? Must be pure. */
    isHostSingletonType(type: T['Type']): boolean;
    /** Render phase: locate the pre-existing instance; throw if it's missing. */
    resolveSingletonInstance(
      type: T['Type'],
      props: T['Props'],
      rootContainer: T['Container'],
      hostContext: T['HostContext'],
      validateDOMNestingDev: boolean,
    ): T['Instance'];
    /** Commit (layout) on mount: wipe foreign state, apply React's props. */
    acquireSingletonInstance(
      type: T['Type'],
      props: T['Props'],
      instance: T['Instance'],
      internalHandle: OpaqueHandle,
    ): void;
    /** Commit on delete: clear only React-owned state — never remove the node. */
    releaseSingletonInstance(
      instance: T['Instance'],
      type: T['Type'],
      props: T['Props'],
    ): void;
    /**
     * Is this singleton an *insertion scope* — do its children get placed inside
     * it rather than in the root container? (react-dom: only `<head>`.) Consulted
     * during placement/deletion host-parent resolution.
     */
    isSingletonScope(type: T['Type']): boolean;
  }

  // ---------------------------------------------------------------------------
  // Host config: test selectors — supportsTestSelectors
  // ---------------------------------------------------------------------------

  /**
   * Backing methods for the experimental test-selector API
   * ({@link Reconciler.findAllNodes} & friends, react-dom's `unstable_testing`
   * entry). All selector exports throw unless `supportsTestSelectors: true` and
   * this family (plus {@link CoreConfig.getInstanceFromNode}) is implemented.
   */
  export interface TestSelectorsConfig<T extends HostConfigTypes = HostConfigTypes> {
    supportsTestSelectors: true;

    /** BFS from any host node back to its FiberRoot. */
    findFiberRoot(node: T['Instance']): null | OpaqueRoot;
    /** Layout rect for {@link Reconciler.findBoundingRects}. */
    getBoundingRect(node: T['Instance']): BoundingRect;
    /** Text content of a host fiber, for text selectors. */
    getTextContent(fiber: OpaqueHandle): string | null;
    /** Whether this subtree is visually hidden (skipped by selector traversal). */
    isHiddenSubtree(fiber: OpaqueHandle): boolean;
    /** Accessibility-role match, for role selectors. */
    matchAccessibilityRole(node: T['Instance'], role: string): boolean;
    /** Focus the node if focusable; `true` on success (backs {@link Reconciler.focusWithin}). */
    setFocusIfFocusable(node: T['Instance'], focusOptions?: object): boolean;
    /** IntersectionObserver factory backing {@link Reconciler.observeVisibleRects}. */
    setupIntersectionObserver(
      targets: Array<T['Instance']>,
      callback: (intersections: Array<{ ratio: number; rect: BoundingRect }>) => void,
      options?: object,
    ): {
      disconnect(): void;
      observe(instance: T['Instance']): void;
      unobserve(instance: T['Instance']): void;
    };
    /** Node → fiber lookup (shared with {@link CoreConfig.getInstanceFromNode}). */
    getInstanceFromNode(node: any): OpaqueHandle | null;
  }

  // ---------------------------------------------------------------------------
  // Host config: view transitions (enableViewTransition is ON by default)
  // ---------------------------------------------------------------------------

  /**
   * `<ViewTransition>` support — **the flag is on by default**, so provide at
   * least the stubs even if your platform has no `document.startViewTransition`
   * analog.
   *
   * @remarks
   * When a commit is view-transition eligible, React defers its *entire*
   * mutation + layout work into your {@link ViewTransitionConfig.startViewTransition}
   * update callback, letting the platform capture "old" pixels first. The name/
   * measure methods bracket that: before the transition React names and measures
   * participating instances; after mutation it re-measures, cancels boundaries
   * that didn't actually change, and lets the platform animate the rest.
   */
  export interface ViewTransitionConfig<T extends HostConfigTypes = HostConfigTypes> {
    /**
     * Run the commit inside your platform's view-transition update callback.
     *
     * @remarks
     * **Stub contract if unsupported** — get this wrong and commits are silently
     * dropped: call `mutationCallback()`, `layoutCallback()`, and
     * `spawnedWorkCallback()` synchronously, in that order, and return `null`
     * ("no transition started"; React proceeds normally).
     *
     * @returns The running transition handle, or `null` when none was started.
     *
     * @example
     * The no-op stub for platforms without view transitions:
     * ```typescript
     * const startViewTransition = (
     *   _state: null,
     *   _container: unknown,
     *   _types: null | string[],
     *   mutationCallback: () => void,
     *   layoutCallback: () => void,
     *   _afterMutationCallback: () => void,
     *   spawnedWorkCallback: () => void,
     * ): null => {
     *   mutationCallback();
     *   layoutCallback();
     *   spawnedWorkCallback();
     *   return null;
     * };
     * ```
     */
    startViewTransition(
      suspendedState: null | T['SuspendedState'],
      rootContainer: T['Container'],
      transitionTypes: null | string[],
      mutationCallback: () => void,
      layoutCallback: () => void,
      afterMutationCallback: () => void,
      spawnedWorkCallback: () => void,
      passiveCallback: () => void,
      errorCallback: (error: unknown) => void,
      blockedCallback: (reason: string) => void,
      finishedAnimation: () => void,
    ): null | T['RunningViewTransition'];
    /** Abort an in-flight transition — newer work superseded it. */
    stopViewTransition(transition: T['RunningViewTransition']): void;
    /** Completion hook; React uses it to release passive effects held during the animation. */
    addViewTransitionFinishedListener(
      transition: T['RunningViewTransition'],
      callback: () => void,
    ): void;
    /** Build the object exposed via `<ViewTransition ref>` (DOM: pseudo-element animation handles). */
    createViewTransitionInstance(name: string): T['ViewTransitionInstance'];
    /** Tag an instance as a named transition participant (DOM: `style.viewTransitionName`). */
    applyViewTransitionName(
      instance: T['Instance'],
      name: string,
      className: string | null | undefined,
    ): void;
    /** Restore whatever the component's own props specified for the name/class. */
    restoreViewTransitionName(instance: T['Instance'], props: T['Props']): void;
    /** A named boundary turned out not to change — untag it and drop its captured snapshot. */
    cancelViewTransitionName(instance: T['Instance'], name: string, props: T['Props']): void;
    /** Strip the implicit whole-document transition group before animating. */
    cancelRootViewTransitionName(rootContainer: T['Container']): void;
    /** Undo {@link ViewTransitionConfig.cancelRootViewTransitionName} after the transition. */
    restoreRootViewTransitionName(rootContainer: T['Container']): void;
    /** Geometry snapshot pre/post mutation (DOM: rect + computed style). */
    measureInstance(instance: T['Instance']): T['InstanceMeasurement'];
    /** {@link ViewTransitionConfig.measureInstance} compensating for the gesture clone's offset. */
    measureClonedInstance(instance: T['Instance']): T['InstanceMeasurement'];
    /** Was it on screen? Off-viewport boundaries don't animate. */
    wasInstanceInViewport(measurement: T['InstanceMeasurement']): boolean;
    /** Did size/position change between snapshots? Unchanged boundaries get cancelled. */
    hasInstanceChanged(
      oldMeasurement: T['InstanceMeasurement'],
      newMeasurement: T['InstanceMeasurement'],
    ): boolean;
    /** Could this resize have reflowed the parent? (Forces the parent to animate too.) */
    hasInstanceAffectedParent(
      oldMeasurement: T['InstanceMeasurement'],
      newMeasurement: T['InstanceMeasurement'],
    ): boolean;
    /** Gesture-only (experimental): clone the root so both gesture states coexist. */
    cloneRootViewTransitionContainer?(rootContainer: T['Container']): T['Instance'];
    /** Gesture-only (experimental): remove the {@link ViewTransitionConfig.cloneRootViewTransitionContainer | root clone}. */
    removeRootViewTransitionClone?(rootContainer: T['Container'], clone: T['Instance']): void;
  }

  // ---------------------------------------------------------------------------
  // Host config: gestures (enableGestureTransition — experimental channel only)
  // ---------------------------------------------------------------------------

  /**
   * Gesture-driven view transitions (`useSwipeTransition`) — experimental channel
   * only; unreachable in OSS stable builds. Also uses
   * {@link CoreConfig.cloneMutableInstance} and the root-clone pair on
   * {@link ViewTransitionConfig}.
   */
  export interface GestureConfig<T extends HostConfigTypes = HostConfigTypes> {
    /**
     * Start a view transition driven by a scroll/pointer timeline instead of time,
     * animating between `rangeStart` and `rangeEnd` offsets.
     */
    startGestureTransition(
      suspendedState: null | T['SuspendedState'],
      rootContainer: T['Container'],
      timeline: T['GestureTimeline'],
      rangeStart: number,
      rangeEnd: number,
      transitionTypes: null | string[],
      mutationCallback: () => void,
      animateCallback: () => void,
      errorCallback: (error: unknown) => void,
      finishedAnimation: () => void,
    ): null | T['RunningViewTransition'];
    /** Current position on the timeline — decides the gesture's start/cancel direction. */
    getCurrentGestureOffset(timeline: T['GestureTimeline']): number;
  }

  // ---------------------------------------------------------------------------
  // Host config: fragment instances (enableFragmentRefs is ON by default)
  // ---------------------------------------------------------------------------

  /**
   * `<Fragment ref={...}>` support — **on by default**. The ref receives a
   * renderer-defined {@link HostConfigTypes.FragmentInstanceType} (react-dom's
   * implements an element-like API — `addEventListener`, `focus`,
   * `getClientRects`… — fanned out over the fragment's current host children).
   * The noop-renderer-sanctioned stub: `createFragmentInstance: () => null` plus
   * no-ops for the other three.
   */
  export interface FragmentInstanceConfig<T extends HostConfigTypes = HostConfigTypes> {
    /** Layout phase, when a `<Fragment ref>` attaches: build the instance. */
    createFragmentInstance(fragmentFiber: OpaqueHandle): T['FragmentInstanceType'];
    /** Repoint the instance at the current fiber after a re-render. */
    updateFragmentInstanceFiber(
      fragmentFiber: OpaqueHandle,
      instance: T['FragmentInstanceType'],
    ): void;
    /** A host child was inserted under the fragment — replay registered listeners/observers onto it. */
    commitNewChildToFragmentInstance(
      childInstance: T['Instance'],
      fragmentInstance: T['FragmentInstanceType'],
    ): void;
    /** A host child left the fragment — remove what {@link FragmentInstanceConfig.commitNewChildToFragmentInstance} added. */
    deleteChildFromFragmentInstance(
      childInstance: T['Instance'],
      fragmentInstance: T['FragmentInstanceType'],
    ): void;
  }

  // ---------------------------------------------------------------------------
  // The assembled host config
  // ---------------------------------------------------------------------------

  /**
   * The object you pass to the {@link Reconciler | Reconciler factory}:
   * {@link CoreConfig} + exactly one of {@link MutationConfig} /
   * {@link PersistenceConfig}, plus the optional feature families, discriminated
   * by their `supportsX` flags.
   *
   * @remarks
   * The npm build reads every field **once at factory time** and has **no
   * fallback shims** — a missing method that gets reached is a raw `TypeError`,
   * and mutating the config afterwards does nothing. View-transition,
   * fragment-instance, and profiling members are typed optional for stub-free
   * prototyping, but their flags are ON in current builds — provide the stubs
   * before shipping (docs/react-reconciler.md §6 has a complete copy-pasteable
   * baseline).
   */
  export type HostConfig<T extends HostConfigTypes = HostConfigTypes> = CoreConfig<T> &
    (MutationConfig<T> | PersistenceConfig<T>) &
    (HydrationConfig<T> | { supportsHydration?: false }) &
    (ResourcesConfig<T> | { supportsResources?: false }) &
    (SingletonsConfig<T> | { supportsSingletons?: false }) &
    (TestSelectorsConfig<T> | { supportsTestSelectors?: false }) &
    Partial<ViewTransitionConfig<T>> &
    Partial<GestureConfig<T>> &
    Partial<FragmentInstanceConfig<T>>;

  // ---------------------------------------------------------------------------
  // The reconciler instance returned by the factory
  // ---------------------------------------------------------------------------

  /**
   * The renderer API returned by the factory — everything your public package
   * (your `createRoot`, `render`, `createPortal`…) is built from.
   */
  export interface Reconciler<T extends HostConfigTypes = HostConfigTypes> {
    // ---- roots ----

    /**
     * Creates a root for `containerInfo`. Renders nothing until
     * {@link Reconciler.updateContainer}.
     *
     * @remarks
     * The three error handlers are required — pass the
     * {@link Reconciler.defaultOnUncaughtError | default handlers} when your public
     * API doesn't expose overrides. For hydration use
     * {@link Reconciler.createHydrationContainer} instead.
     *
     * @param containerInfo - Your host container object.
     * @param tag - Always `ConcurrentRoot` (1); legacy mode is compiled out.
     * @param hydrationCallbacks - Pass `null` (flag-gated, off in OSS).
     * @param isStrictMode - StrictMode for the whole root.
     * @param concurrentUpdatesByDefaultOverride - **Ignored** — pass `null`.
     * @param identifierPrefix - `useId` prefix; keeps ids unique across multiple roots.
     * @param onUncaughtError - Error no boundary caught.
     * @param onCaughtError - Error a boundary caught.
     * @param onRecoverableError - React recovered on its own (e.g. hydration mismatch → client render).
     * @param onDefaultTransitionIndicator - Show a pending indicator for default
     *   transitions; optionally return a cleanup function.
     * @param transitionCallbacks - Pass `null` (Transition Tracing, off in OSS).
     * @returns The opaque root to hold and pass to {@link Reconciler.updateContainer}.
     *
     * @example
     * The standard wiring inside a renderer's `createRoot`:
     * ```typescript
     * const root = reconciler.createContainer(
     *   container, ConcurrentRoot, null, false, null, '',
     *   reconciler.defaultOnUncaughtError,
     *   reconciler.defaultOnCaughtError,
     *   reconciler.defaultOnRecoverableError,
     *   () => {}, null,
     * );
     * reconciler.updateContainer(element, root, null, null);
     * ```
     */
    createContainer(
      containerInfo: T['Container'],
      tag: RootTag,
      hydrationCallbacks: null | SuspenseHydrationCallbacks<
        T['SuspenseInstance'],
        T['ActivityInstance']
      >,
      isStrictMode: boolean,
      concurrentUpdatesByDefaultOverride: null | boolean,
      identifierPrefix: string,
      onUncaughtError: (error: unknown, errorInfo: ErrorInfo) => void,
      onCaughtError: (error: unknown, errorInfo: CaughtErrorInfo) => void,
      onRecoverableError: (error: unknown, errorInfo: ErrorInfo) => void,
      onDefaultTransitionIndicator: () => void | (() => void),
      transitionCallbacks: null | TransitionTracingCallbacks,
    ): OpaqueRoot;

    /**
     * Creates a hydration root **and schedules its initial render** — do not call
     * {@link Reconciler.updateContainer} for the first render of a hydration root.
     * Requires {@link CoreConfig.supportsHydration}.
     *
     * @param initialChildren - The element tree; must match the server output.
     * @param callback - Legacy-mode leftover; pass `null`.
     * @param formState - Postback state for `useActionState` hydration, or `null`.
     */
    createHydrationContainer(
      initialChildren: ReactNodeList,
      callback: (() => void) | null | undefined,
      containerInfo: T['Container'],
      tag: RootTag,
      hydrationCallbacks: null | SuspenseHydrationCallbacks<
        T['SuspenseInstance'],
        T['ActivityInstance']
      >,
      isStrictMode: boolean,
      concurrentUpdatesByDefaultOverride: null | boolean,
      identifierPrefix: string,
      onUncaughtError: (error: unknown, errorInfo: ErrorInfo) => void,
      onCaughtError: (error: unknown, errorInfo: CaughtErrorInfo) => void,
      onRecoverableError: (error: unknown, errorInfo: ErrorInfo) => void,
      onDefaultTransitionIndicator: () => void | (() => void),
      transitionCallbacks: null | TransitionTracingCallbacks,
      formState: unknown | null,
    ): OpaqueRoot;

    // ---- updates ----

    /**
     * Schedules a render of `element` into the root — the engine behind your
     * `root.render()`. Asynchronous: work flows through your microtask/Scheduler
     * integration, then commits.
     *
     * @remarks
     * Priority comes from context — inside `startTransition` it's a transition
     * lane; otherwise whatever {@link CoreConfig.resolveUpdatePriority} reports.
     *
     * @param element - The tree to render; **`null` unmounts** (that's how
     *   `root.unmount()` works).
     * @param callback - Fires after the commit.
     * @returns The {@link Lane} the update was scheduled at; safe to ignore.
     */
    updateContainer(
      element: ReactNodeList,
      container: OpaqueRoot,
      parentComponent?: Component<any, any> | null,
      callback?: (() => void) | null,
    ): Lane;
    /**
     * {@link Reconciler.updateContainer} forced onto the sync lane. Only
     * *schedules* — call {@link Reconciler.flushSyncWork} afterwards to actually
     * flush synchronously (the classic `ReactDOM.render` pairing).
     */
    updateContainerSync(
      element: ReactNodeList,
      container: OpaqueRoot,
      parentComponent?: Component<any, any> | null,
      callback?: (() => void) | null,
    ): Lane;

    // ---- sync/batching ----

    /**
     * Flushes pending sync-lane work on all roots, unless already mid-render.
     * @returns `true` if it could **not** flush (note the inversion).
     */
    flushSyncWork(): boolean;
    /** Legacy-flavored `flushSync(fn)` retained for old semantics; prefer {@link Reconciler.flushSyncWork}. */
    flushSyncFromReconciler<R>(fn?: () => R): R | void;
    /** Flushes pending passive effects now; `true` if any ran. Call before reading effect-dependent state. */
    flushPassiveEffects(): boolean;
    /** `true` inside render or commit — for "cannot update during render"-style guards. */
    isAlreadyRendering(): boolean;
    /** Vestigial: a passthrough in concurrent-only builds. Kept for API compatibility. */
    batchedUpdates<A, R>(fn: (a: A) => R, a: A): R;
    /** Runs `fn` with update priority forced to `DefaultEventPriority`. */
    deferredUpdates<A>(fn: () => A): A;
    /** Runs `fn` at `DiscreteEventPriority` — for replaying discrete events. */
    discreteUpdates<A, B, C, D, R>(fn: (a: A, b: B, c: C, d: D) => R, a: A, b: B, c: C, d: D): R;

    // ---- instances & lookup ----

    /** Public instance of the root's first child — what a legacy `render` would return. */
    getPublicRootInstance(
      container: OpaqueRoot,
    ): Component<any, any> | T['PublicInstance'] | null;
    /**
     * Nearest host instance below a component instance — the `findDOMNode`
     * primitive. Throws on unmounted components; prefer refs in new API surface.
     */
    findHostInstance(component: object): T['PublicInstance'] | null;
    /** {@link Reconciler.findHostInstance} + a StrictMode deprecation warning attributed to `methodName`. */
    findHostInstanceWithWarning(
      component: object,
      methodName: string,
    ): T['PublicInstance'] | null;
    /** Takes a {@link Fiber} (not a component) and skips portal subtrees — focus/a11y traversal. */
    findHostInstanceWithNoPortals(fiber: Fiber): T['PublicInstance'] | null;

    // ---- selective hydration (call from your event system) ----

    /**
     * A **discrete** event targeted a dehydrated boundary: hydrate it synchronously
     * so the event can be handled. The trio's fiber comes from your
     * node → fiber index (see {@link CoreConfig.getInstanceFromNode}).
     */
    attemptSynchronousHydration(fiber: Fiber): void;
    /** Continuous-event variant (mouseover): schedules hydration at SelectiveHydrationLane. */
    attemptContinuousHydration(fiber: Fiber): void;
    /** Everything-else variant: hydrates at the current resolved priority. */
    attemptHydrationAtCurrentPriority(fiber: Fiber): void;

    // ---- portals ----

    /**
     * Builds the portal element object. Wrap it as your public
     * `createPortal(children, container)` with `implementation: null`.
     */
    createPortal(
      children: ReactNodeList,
      containerInfo: T['Container'],
      implementation: unknown,
      key?: string | null,
    ): ReactPortal;

    // ---- form actions ----

    /**
     * Starts a transition for a form action on a `<form>`-like host fiber — call
     * from your submit-event plumbing (react-dom's form plugin does exactly this).
     * Requires {@link CoreConfig.NotPendingTransition} / {@link CoreConfig.HostTransitionContext}.
     *
     * @param pendingState - The {@link HostConfigTypes.TransitionStatus} value
     *   `useFormStatus` should observe while the action runs.
     */
    startHostTransition<F>(
      formFiber: Fiber,
      pendingState: T['TransitionStatus'],
      action: ((formData: F) => unknown) | null,
      formData: F,
    ): void;

    // ---- error handler defaults (for your createRoot options fallbacks) ----

    /** Default: report via `reportGlobalError` (+ DEV console note). Use as the `onUncaughtError` fallback. */
    defaultOnUncaughtError(error: unknown, errorInfo: ErrorInfo): void;
    /** Default: DEV `console.error` naming the boundary. Use as the `onCaughtError` fallback. */
    defaultOnCaughtError(error: unknown, errorInfo: CaughtErrorInfo): void;
    /** Default: report via `reportGlobalError`. Use as the `onRecoverableError` fallback. */
    defaultOnRecoverableError(error: unknown, errorInfo: ErrorInfo): void;

    // ---- DevTools ----

    /**
     * Registers this renderer with React DevTools.
     *
     * @remarks
     * **Zero-arg now** — the old `devToolsConfig` parameter is gone. Renderer
     * identity comes from the host-config fields
     * {@link CoreConfig.rendererVersion}, {@link CoreConfig.rendererPackageName},
     * and {@link CoreConfig.extraDevToolsConfig}; set those, then call this once
     * at module init.
     *
     * @returns `false` when no DevTools global hook is present (not an error —
     *   DevTools just isn't installed).
     */
    injectIntoDevTools(): boolean;

    // ---- DevTools testing trampolines (rarely called directly) ----

    /** Trampoline for DevTools' "force error" feature; consumed internally. */
    shouldError(fiber: Fiber): boolean | undefined | null;
    /** Trampoline for DevTools' "force suspend" feature; consumed internally. */
    shouldSuspend(fiber: Fiber): boolean;

    // ---- test selectors (throw unless supportsTestSelectors) ----

    /** Selector: matches fibers of the given component function/class. */
    createComponentSelector(component: unknown): TestSelector;
    /** Selector: matches nodes whose subtree satisfies all inner `selectors`. */
    createHasPseudoClassSelector(selectors: TestSelector[]): TestSelector;
    /** Selector: matches by accessibility role (via {@link TestSelectorsConfig.matchAccessibilityRole}). */
    createRoleSelector(role: string): TestSelector;
    /** Selector: matches by text content (via {@link TestSelectorsConfig.getTextContent}). */
    createTextSelector(text: string): TestSelector;
    /** Selector: matches your `data-testname` equivalent. */
    createTestNameSelector(id: string): TestSelector;
    /** All host instances under `hostRoot` matching the selector chain. */
    findAllNodes(hostRoot: T['Instance'], selectors: TestSelector[]): Array<T['Instance']>;
    /** Human-readable explanation of where a selector chain stopped matching. */
    getFindAllNodesFailureDescription(
      hostRoot: T['Instance'],
      selectors: TestSelector[],
    ): string | null;
    /** Bounding rects of all matches (merged where adjacent). */
    findBoundingRects(hostRoot: T['Instance'], selectors: TestSelector[]): BoundingRect[];
    /** Focus the first focusable match; `true` on success. */
    focusWithin(hostRoot: T['Instance'], selectors: TestSelector[]): boolean;
    /** Observe viewport intersection of all matches; disconnect via the returned handle. */
    observeVisibleRects(
      hostRoot: T['Instance'],
      selectors: TestSelector[],
      callback: (intersections: Array<{ ratio: number; rect: BoundingRect }>) => void,
      options?: object,
    ): { disconnect: () => void };
  }

  /**
   * The factory: pass a {@link HostConfig}, get a {@link Reconciler}.
   *
   * @remarks
   * The npm bundle is literally `module.exports = function $$$reconciler($$$config) { … }` —
   * config fields are destructured once into module constants, so late mutation of
   * the object has no effect, and nothing validates completeness up front.
   *
   * @typeParam T - Your {@link HostConfigTypes} extension; inferred from the
   *   config when you annotate it, or pass explicitly: `Reconciler<MyTypes>(config)`.
   *
   * @example
   * The end-to-end shape of a renderer package:
   * ```typescript
   * import Reconciler, { type HostConfig } from 'react-reconciler';
   * import { ConcurrentRoot } from 'react-reconciler/constants';
   *
   * declare const hostConfig: HostConfig<MyTypes>;
   * declare const container: MyRootNode;
   * declare const element: unknown;
   *
   * const reconciler = Reconciler(hostConfig);
   * const root = reconciler.createContainer(
   *   container, ConcurrentRoot, null, false, null, '',
   *   reconciler.defaultOnUncaughtError,
   *   reconciler.defaultOnCaughtError,
   *   reconciler.defaultOnRecoverableError,
   *   () => {}, null,
   * );
   * reconciler.updateContainer(element, root, null, null);  // render
   * reconciler.updateContainer(null, root, null, null);     // unmount
   * ```
   */
  export default function Reconciler<T extends HostConfigTypes = HostConfigTypes>(
    config: HostConfig<T>,
  ): Reconciler<T>;
}

declare module 'react-reconciler/constants' {
  import type { EventPriority, RootTag } from 'react-reconciler';

  export type { EventPriority, RootTag };

  /**
   * "Nothing stored" sentinel for your update-priority slot (value `0`).
   * Never return it from `resolveUpdatePriority` — it means "unset", not "default".
   */
  export const NoEventPriority: EventPriority; // 0
  /**
   * Intentional, discrete user input — click, keydown (value `2` = SyncLane).
   * Interrupts everything; never batched across time.
   */
  export const DiscreteEventPriority: EventPriority; // 2
  /**
   * Continuous user input the user can't count — mousemove, scroll, drag
   * (value `8` = InputContinuousLane). Interrupts background work; may be batched.
   */
  export const ContinuousEventPriority: EventPriority; // 8
  /** Everything that isn't user input (value `32` = DefaultLane). The usual fallback. */
  export const DefaultEventPriority: EventPriority; // 32
  /** Idle/offscreen work (value `536870912` = IdleLane). Runs when nothing else needs to. */
  export const IdleEventPriority: EventPriority; // 536870912

  /** Root tag `0`. Legacy mode is compiled out of OSS builds — do not use. */
  export const LegacyRoot: RootTag; // 0
  /** Root tag `1` — the one to pass to `createContainer`. */
  export const ConcurrentRoot: RootTag; // 1
}

declare module 'react-reconciler/reflection' {
  import type { Fiber } from 'react-reconciler';

  /** Nearest mounted fiber at or above the given one; `null` if the tree is unmounted. */
  export function getNearestMountedFiber(fiber: Fiber): null | Fiber;
  /**
   * Nearest host fiber *below* a component fiber — the primitive under
   * `findDOMNode`-style APIs. Its `stateNode` is your instance.
   */
  export function findCurrentHostFiber(parent: Fiber): Fiber | null;
  /** {@link findCurrentHostFiber} that refuses to cross portal boundaries. */
  export function findCurrentHostFiberWithNoPortals(parent: Fiber): Fiber | null;
  /**
   * Resolves which of the fiber/alternate pair is the *current* one — needed
   * because every fiber has a work-in-progress twin. Throws if unmounted.
   */
  export function findCurrentFiberUsingSlowPath(fiber: Fiber): Fiber | null;
  /** The container of the root this fiber belongs to, if it's attached to one. */
  export function getContainerFromFiber(fiber: Fiber): null | unknown;
  /** Is `childFiber` inside `parentFiber`'s subtree (inclusive)? */
  export function doesFiberContain(parentFiber: Fiber, childFiber: Fiber): boolean;
  /** Is this a Suspense fiber currently showing its fallback? */
  export function isFiberSuspenseAndTimedOut(fiber: Fiber): boolean;
  /** The dehydrated Suspense marker instance held by this fiber, if any. */
  export function getSuspenseInstanceFromFiber(fiber: Fiber): null | unknown;
  /** The dehydrated `<Activity>` marker instance held by this fiber, if any. */
  export function getActivityInstanceFromFiber(fiber: Fiber): null | unknown;
  // Additional fragment-instance traversal helpers exist but are internal to
  // react-dom's FragmentInstance implementation; intentionally not typed here.
}
