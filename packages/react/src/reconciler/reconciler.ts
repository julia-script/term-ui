import {
  type DOMEvent,
  type Element,
  type InputEvent,
  TextElement,
} from "@term-ui/dom";
import kebabCase from "lodash-es/kebabCase";
import createReconciler, {
  type HostConfig,
  type HostConfigTypes,
} from "react-reconciler";
import {
  ContinuousEventPriority,
  DefaultEventPriority,
  DiscreteEventPriority,
  type EventPriority,
  NoEventPriority,
} from "react-reconciler/constants";
import type { TermUi } from "../TermUi.js";

type ElementType = "text" | "view";
type Props = Record<string, unknown>;
const NO_CONTEXT: object = {};

interface TermUiTypes extends HostConfigTypes {
  Type: ElementType;
  Props: Props;
  Container: TermUi;
  Instance: Element;
  TextInstance: TextElement;
  PublicInstance: Element | TextElement;
  HostContext: object;
  TimeoutHandle: ReturnType<typeof setTimeout>;
  NoTimeout: -1;
  SuspendedState: null;
  TransitionStatus: null;
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

type DomEventName =
  | "click"
  | "mouseenter"
  | "mouseleave"
  | "mousemove"
  | "mousedown"
  | "mouseup"
  | "scroll";
type EventHandler = (event: DOMEvent) => void;

const propToEventMap: Record<
  string,
  DomEventName
> = {
  onClick: "click",
  onMouseEnter: "mouseenter",
  onMouseLeave: "mouseleave",
  onMouseMove: "mousemove",
  onMouseDown: "mousedown",
  onMouseUp: "mouseup",
  onScroll: "scroll",
};

const attachEventHandlers = (
  instance: Element,
  props: Props,
  oldProps?: Props,
) => {
  for (const [
    propName,
    eventName,
  ] of Object.entries(propToEventMap)) {
    const oldHandler = oldProps?.[propName] as
      | EventHandler
      | undefined;
    const newHandler = props[propName] as
      | EventHandler
      | undefined;
    if (oldHandler === newHandler) continue;
    if (oldHandler) {
      instance.removeEventListener(
        eventName,
        oldHandler,
      );
    }
    if (newHandler) {
      instance.addEventListener(
        eventName,
        newHandler,
      );
    }
  }
};

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------

const isPlainObject = (
  value: unknown,
): value is Record<string, unknown> => {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value)
  );
};

const styleStringFromProps = (
  kind: ElementType,
  propStyles: unknown,
): string => {
  const styles: Record<string, unknown> =
    kind === "text"
      ? { display: "inline flow" }
      : {};
  if (isPlainObject(propStyles)) {
    Object.assign(styles, propStyles);
  }
  return Object.entries(styles)
    .map(
      ([key, value]) =>
        `${kebabCase(key)}: ${value}`,
    )
    .join(";");
};

// Suspense visibility: hidden instances keep their layout state but are
// removed from layout/paint/hit-testing via a composed `display: none`.
// The reconciler owns every style string it sets, so composition is safe.
const lastStyles = new WeakMap<Element, string>();
const hiddenInstances = new WeakSet<Element>();
const hiddenTexts = new WeakSet<TextElement>();

const applyStyle = (
  instance: Element,
  style: string,
) => {
  lastStyles.set(instance, style);
  instance.setStyle(
    hiddenInstances.has(instance)
      ? `${style};display: none`
      : style,
  );
};

const disposeInstance = (
  instance: Element | TextElement,
) => {
  if (!instance.isDisposed()) {
    instance.dispose();
  }
};

// ---------------------------------------------------------------------------
// Update priority
// ---------------------------------------------------------------------------

let currentUpdatePriority: EventPriority =
  NoEventPriority;

export const inputEventPriority = (
  event: InputEvent,
): EventPriority => {
  if (event.kind === "key") {
    return DiscreteEventPriority;
  }
  if (
    event.kind === "mouse" ||
    event.kind === "mouse-legacy"
  ) {
    return event.action === "press" ||
      event.action === "release"
      ? DiscreteEventPriority
      : ContinuousEventPriority;
  }
  return DefaultEventPriority;
};

/**
 * Brackets an input-event dispatch so state updates from handlers are
 * scheduled at the right priority: discrete for keys/clicks, continuous
 * for motion/wheel. Wire as `DocumentOptions.wrapInputDispatch`.
 */
export const runWithInputEventPriority = (
  event: InputEvent,
  dispatch: () => void,
) => {
  const previous = currentUpdatePriority;
  currentUpdatePriority =
    inputEventPriority(event);
  try {
    dispatch();
  } finally {
    currentUpdatePriority = previous;
  }
};

// ---------------------------------------------------------------------------
// Host config
// ---------------------------------------------------------------------------

const hostConfig: HostConfig<TermUiTypes> = {
  // ---- mode ----
  supportsMutation: true,
  supportsPersistence: false,
  supportsHydration: false,
  isPrimaryRenderer: true,
  warnsIfNotActing: false,
  supportsMicrotasks: true,
  scheduleMicrotask: queueMicrotask,

  // ---- timers ----
  scheduleTimeout: setTimeout,
  cancelTimeout: clearTimeout,
  noTimeout: -1,

  // ---- update priority ----
  setCurrentUpdatePriority: (priority) => {
    currentUpdatePriority = priority;
  },
  getCurrentUpdatePriority: () =>
    currentUpdatePriority,
  resolveUpdatePriority: () => {
    if (currentUpdatePriority !== NoEventPriority)
      return currentUpdatePriority;
    return DefaultEventPriority;
  },
  shouldAttemptEagerTransition: () => false,

  // ---- host context ----
  // note: a non-null sentinel is required — the 0.33 dev build treats a
  // null host context as missing ("Expected host context to exist")
  getRootHostContext: () => NO_CONTEXT,
  getChildHostContext: (parentHostContext) =>
    parentHostContext,

  // ---- creation (render phase — instances are detached) ----
  createInstance: (type, props, termUi) => {
    const node =
      termUi.document.createElement(type);
    applyStyle(
      node,
      styleStringFromProps(type, props.style),
    );
    if (props.contentEditable) {
      node.setAttribute(
        "contenteditable",
        "true",
      );
    }
    attachEventHandlers(node, props);
    return node;
  },
  createTextInstance: (text, termUi) => {
    return termUi.document.createTextNode(text);
  },
  appendInitialChild: (parent, child) => {
    parent.appendChild(child);
  },
  finalizeInitialChildren: () => false,
  shouldSetTextContent: () => false,
  getPublicInstance: (instance) => instance,

  // ---- commit lifecycle ----
  prepareForCommit: () => null,
  resetAfterCommit: (termUi) => {
    termUi.render();
  },
  clearContainer: (termUi) => {
    termUi.document.root.removeChildren();
  },
  preparePortalMount: () => {},

  // ---- mutation ----
  appendChild: (parent, child) => {
    parent.appendChild(child);
  },
  appendChildToContainer: (termUi, child) => {
    termUi.document.root.appendChild(child);
  },
  insertBefore: (parent, child, beforeChild) => {
    parent.insertBefore(child, beforeChild);
  },
  insertInContainerBefore: (
    termUi,
    child,
    beforeChild,
  ) => {
    termUi.document.root.insertBefore(
      child,
      beforeChild,
    );
  },
  removeChild: (parent, child) => {
    parent.removeChild(child);
    // React never calls detachDeletedInstance for text fibers; a topmost
    // deleted text node would otherwise leak its native handle
    if (child instanceof TextElement) {
      disposeInstance(child);
    }
  },
  removeChildFromContainer: (termUi, child) => {
    termUi.document.root.removeChild(child);
    if (child instanceof TextElement) {
      disposeInstance(child);
    }
  },
  commitUpdate: (
    instance,
    type,
    oldProps,
    newProps,
  ) => {
    const prevStyle = styleStringFromProps(
      type,
      oldProps.style,
    );
    const nextStyle = styleStringFromProps(
      type,
      newProps.style,
    );
    if (
      prevStyle !== nextStyle ||
      !lastStyles.has(instance)
    ) {
      applyStyle(instance, nextStyle);
    }
    const prevEditable =
      !!oldProps.contentEditable;
    const nextEditable =
      !!newProps.contentEditable;
    if (prevEditable !== nextEditable) {
      if (nextEditable) {
        instance.setAttribute(
          "contenteditable",
          "true",
        );
      } else {
        instance.removeAttribute(
          "contenteditable",
        );
      }
    }
    attachEventHandlers(
      instance,
      newProps,
      oldProps,
    );
  },
  commitTextUpdate: (
    instance,
    oldText,
    newText,
  ) => {
    if (newText === oldText) return;
    // hidden text nodes stay blank; unhideTextInstance restores the
    // latest committed text
    if (hiddenTexts.has(instance)) return;
    instance.setText(newText);
  },
  commitMount: () => {},
  resetTextContent: () => {},

  // ---- visibility (Suspense / <Activity>) ----
  hideInstance: (instance) => {
    hiddenInstances.add(instance);
    applyStyle(
      instance,
      lastStyles.get(instance) ?? "",
    );
  },
  unhideInstance: (instance, props) => {
    hiddenInstances.delete(instance);
    applyStyle(
      instance,
      lastStyles.get(instance) ?? "",
    );
    // props are authoritative if we never saw a style for this instance
    if (!lastStyles.has(instance)) {
      applyStyle(
        instance,
        styleStringFromProps(
          "view",
          props.style,
        ),
      );
    }
  },
  hideTextInstance: (instance) => {
    hiddenTexts.add(instance);
    instance.setText("");
  },
  unhideTextInstance: (instance, text) => {
    hiddenTexts.delete(instance);
    instance.setText(text);
  },

  // ---- deletion (passive phase; React has fully detached the node) ----
  detachDeletedInstance: (instance) => {
    if (instance.isDisposed()) return;
    // React only detaches host *components* (fiber.tag === 5); text
    // children never get their own callback, so free them with their parent
    for (const child of instance.getChildren()) {
      if (child instanceof TextElement) {
        disposeInstance(child);
      }
    }
    instance.dispose();
  },

  // ---- suspensey commits (nothing to wait for in a terminal) ----
  maySuspendCommit: () => false,
  maySuspendCommitOnUpdate: () => false,
  maySuspendCommitInSyncRender: () => false,
  preloadInstance: () => true,
  startSuspendingCommit: () => null,
  suspendInstance: () => {},
  suspendOnActiveViewTransition: () => {},
  waitForCommitToBeReady: () => null,
  getSuspendedCommitReason: () => null,

  // ---- profiling hooks (live in dev builds) ----
  trackSchedulerEvent: () => {},
  resolveEventType: () => null,
  resolveEventTimeStamp: () => -1.1,

  // ---- forms (no forms in a terminal; sentinel plumbing only) ----
  NotPendingTransition: null,
  HostTransitionContext: {
    $$typeof: Symbol.for("react.context"),
    Provider: null,
    Consumer: null,
    _currentValue: null,
    _currentValue2: null,
    _threadCount: 0,
    // biome-ignore lint/suspicious/noExplicitAny: raw context-shaped object per host contract
  } as any,
  resetFormInstance: () => {},

  // ---- view transitions (stub contract: run commit phases synchronously) ----
  startViewTransition: (
    _state,
    _container,
    _types,
    mutationCb,
    layoutCb,
    _afterMutationCb,
    spawnedWorkCb,
  ) => {
    mutationCb();
    layoutCb();
    spawnedWorkCb();
    return null;
  },
  applyViewTransitionName: () => {},
  restoreViewTransitionName: () => {},
  cancelViewTransitionName: () => {},
  cancelRootViewTransitionName: () => {},
  restoreRootViewTransitionName: () => {},
  measureInstance: () => null,
  measureClonedInstance: () => null,
  wasInstanceInViewport: () => false,
  hasInstanceChanged: () => false,
  hasInstanceAffectedParent: () => false,
  stopViewTransition: () => {},
  addViewTransitionFinishedListener: () => {},
  createViewTransitionInstance: (name) => ({
    name,
  }),

  // ---- fragment refs (stubbed; <Fragment ref> resolves to null) ----
  createFragmentInstance: () => null,
  updateFragmentInstanceFiber: () => {},
  commitNewChildToFragmentInstance: () => {},
  deleteChildFromFragmentInstance: () => {},

  // ---- misc ----
  getInstanceFromNode: () => null,
  beforeActiveInstanceBlur: () => {},
  afterActiveInstanceBlur: () => {},
  prepareScopeUpdate: () => {},
  getInstanceFromScope: () => null,
  requestPostPaintCallback: () => {},
  bindToConsole: (methodName, args) =>
    Function.prototype.bind.apply(
      // biome-ignore lint/suspicious/noExplicitAny: console indexed by method name
      (console as any)[methodName],
      // biome-ignore lint/suspicious/noExplicitAny: bind tuple
      [console].concat(args) as any,
    ),

  // ---- DevTools identity ----
  rendererVersion: "0.0.2",
  rendererPackageName: "@term-ui/react",
  extraDevToolsConfig: null,
};

export const reconciler =
  createReconciler<TermUiTypes>(hostConfig);
