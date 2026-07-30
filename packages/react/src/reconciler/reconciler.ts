import {
  Document,
  type DOMEvent,
  type Element,
  TextElement,
} from "@term-ui/dom";
import kebabCase from "lodash-es/kebabCase";
import _createReconciler from "react-reconciler";
import {
  DefaultEventPriority,
  type EventPriority,
} from "react-reconciler/constants";
import type { TermUi } from "../TermUi.js";

const noop =
  <T>(value?: T) =>
  () =>
    value;
type ElementType = "text" | "view";
type Props = Record<string, unknown>;
type HostContext = {};
const NO_CONTEXT: HostContext = {};

// Types for event handling
type MouseEventName =
  | "click"
  | "mouseenter"
  | "mouseleave"
  | "mousemove"
  | "mousedown"
  | "mouseup";
type EventHandler = (event: DOMEvent) => void;

// Map from React prop names to DOM event names
const propToEventMap: Record<
  string,
  MouseEventName
> = {
  onClick: "click",
  onMouseEnter: "mouseenter",
  onMouseLeave: "mouseleave",
  onMouseMove: "mousemove",
  onMouseDown: "mousedown",
  onMouseUp: "mouseup",
};

const createReconciler: typeof _createReconciler =
  (options) => {
    return _createReconciler(logCalls(options));
  };
// Function to attach event handlers
const attachEventHandlers = (
  instance: TextElement | Element,
  props: Props,
  oldProps?: Props,
) => {
  if (instance instanceof TextElement) {
    throw new Error(
      "attachEventHandlers: instance is a TextElement",
    );
  }
  // instance.removeEventListener("scroll", oldProps?.onScroll);
  // For each possible event prop
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

    // Remove old handler if it exists and is different from new handler
    if (oldHandler && oldHandler !== newHandler) {
      instance.removeEventListener(
        eventName,
        oldHandler,
      );
    }

    // Add new handler if it exists
    if (newHandler && newHandler !== oldHandler) {
      instance.addEventListener(
        eventName,
        newHandler,
      );
    }
  }
};

const stringifyStyles = (
  styles: Record<string, unknown>,
) => {
  return Object.entries(styles)
    .map(
      ([key, value]) =>
        `${kebabCase(key)}: ${value}`,
    )
    .join(";");
};

const normalizeStyle = (
  kind: ElementType,
  propStyles?: unknown,
) => {
  const styles: Record<string, unknown> = {};
  if (kind === "text") {
    return {
      display: "inline flow",
      ...(isPlainObject(propStyles)
        ? propStyles
        : {}),
    };
  }
  if (isPlainObject(propStyles)) {
    return {
      ...styles,
      ...propStyles,
    };
  }
  return styles;
};

// Store props on node instances
// class NodeWithProps extends BlockNode {
//   _props?: Props;
//   constructor(node: Node, props?: Props) {
//     super(node.tree, node.id);
//     this._props = props;
//   }
// }
const isPlainObject = (
  value: unknown,
): value is Record<string, unknown> => {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value)
  );
};
import fs from "node:fs";
import { inspect } from "node:util";
const logFile = fs.createWriteStream(
  "./reconciler.log",
);
const stringify = (value: unknown) => {
  const refs = new Set<unknown>();
  return JSON.stringify(
    value,
    (key, value) => {
      if (typeof value === "function") {
        return `[Function ${value.name || "anonymous"}]`;
      }
      if (typeof value === "symbol") {
        return `[Symbol ${value.toString()}]`;
      }
 
      if (typeof value === "object" && value !== null) {
        if (refs.has(value)) {
          return "[Ref]";
        }
        refs.add(value);
        return value;
      }
      if (Array.isArray(value)) {
        if (refs.has(value)) {
          return "[Circular Array]";
        }
        refs.add(value);
        return value;
      }

      return value;
    },
    2,
  );
};
const logCalls = <T>(obj: T) => {
  // @ts-expect-error
  const entries = Object.entries(obj).map(
    ([key, value]) => {
      if (typeof value === "function") {
        return [
          key,
          // biome-ignore lint/suspicious/noExplicitAny: <explanation>
          (...args: any[]) => {
            try {
              
              logFile.write(
                `${key} ${inspect(args, { depth: 1, colors: true })}\n`,
              );
              const res = value.apply(obj, args);
              return res;
            } catch (e) {
              logFile.write(
                `ERROR: ${key} ${inspect(args, { depth: 2, colors: true })}\n\n${e}\n`,
              );
              throw e;
            }
          },
        ];
      }
      return [key, value];
    },
  );
  return Object.fromEntries(entries) as T;
};

let currentUpdatePriority: EventPriority =
  DefaultEventPriority;
const _reconciler = createReconciler({
  supportsMutation: true,
  supportsPersistence: false,
  supportsMicrotasks: true,

  isPrimaryRenderer: true,

  noTimeout: -1,
  scheduleTimeout: setTimeout,
  cancelTimeout: clearTimeout,

  createInstance: (
    type: ElementType,
    props: Props,
    termUi: TermUi,
    _hostContext: HostContext,
    _internalHandle: unknown,
  ) => {
    // console.log("createInstance", type, props);
    // if (type === "term-text") {
    //   // console.log("createTextInstance", props);
    //   return termUi.document.createElement(
    //     "text",
    //   );
    // }
    const styles = normalizeStyle(
      type,
      props?.style,
    );

    const style = stringifyStyles(styles);
    const node =
      termUi.document.createElement(type);
    node.setStyle(style);
    if (props?.contentEditable) {
      node.setAttribute(
        "contenteditable",
        "true",
      );
    }

    // Attach event handlers on instance creation
    attachEventHandlers(node, props);

    return node;
  },

  createTextInstance: (
    text: string,
    termUi: TermUi,
    _hostContext: HostContext,
  ) => {
    // console.log("createTextInstance", text);
    const node =
      termUi.document.createTextNode(text);
    return node;
  },
  scheduleMicrotask: queueMicrotask,
  getCurrentUpdatePriority: () =>
    currentUpdatePriority,

  resolveUpdatePriority: () =>
    currentUpdatePriority,
  setCurrentUpdatePriority: (priority) => {
    currentUpdatePriority = priority;
  },
  getPublicInstance: (instance) => instance,

  shouldSetTextContent: (type, props) => {
    // console.log("shouldSetTextContent", type, props);
    return false 
  },

  getRootHostContext: () => NO_CONTEXT,
  getChildHostContext: (parentContext) =>
    parentContext,
  finalizeInitialChildren: () => false,
  prepareForCommit: () => null,
  resetAfterCommit: (tui) => {
    try {
      tui.render();
    } catch (e) {
      console.error(e);
    }
  },
  detachDeletedInstance: (instance) => {
    // if (instance instanceof TextElement) {
    //   instance.dispose();
    //   return ;
    // }
    if (instance.isDisposed()) {
      return;
    }
    // instance.dispose();
  },

  appendInitialChild: (parent, child) => {
    // console.log("appendInitialChild", parent, child);
    if (parent instanceof TextElement) {
      throw new Error(
        "appendInitialChild: parent is not a NodeWithProps",
      );
    }
    parent.appendChild(child);
  },

  appendChildToContainer: (tui, child) => {
    tui.document.root.appendChild(child);
  },
  appendChild: (parent, child) => {
    // console.log("appendChild", parent, child);
    parent.appendChild(child);
  },
  insertBefore: (parent, child, before) => {
    // console.log("insertBefore", parent, child, before);
    parent.insertBefore(child, before);
  },
  removeChild: (parentInstance, child) => {
    if (parentInstance instanceof TextElement) {
      throw new Error(
        "removeChild: parentInstance is not a NodeWithProps",
      );
    }

    parentInstance.removeChild(child);

    // console.log("removeChild", parentInstance);
  },

  removeChildFromContainer: (tui, child) => {
    tui.document.root.removeChild(child);
  },

  clearContainer: (tui) => {
    tui.document.root.removeChildren();
  },
  // resetTextContent(instance) {
  //   if (instance instanceof TextElement) {
  //     instance.setText("");
  //   }
  //   // if (instance instanceof TextElement) {
  //   // }
  // },

  commitTextUpdate: (
    instance,
    oldText,
    newText,
  ) => {
    // debug.log(instance.id, newText, oldText);
    if (instance instanceof TextElement) {
      if (newText === oldText) {
        return;
      }
      // debug.log("setText", newText);
      instance.setText(newText);
      return;
    }
    throw new Error(
      "commitTextUpdate: instance is not a TextElement",
    );
  },

  commitUpdate: (
    instance,
    type,
    oldProps,
    newProps,
  ) => {
    // TODO: better diffing
    // if (instance instanceof TextNode) {
    //   return;
    // }

    const prevStyle = isPlainObject(
      oldProps?.style,
    )
      ? stringifyStyles(
          normalizeStyle(type, oldProps?.style),
        )
      : "";
    const newStyle = isPlainObject(
      newProps?.style,
    )
      ? stringifyStyles(
          normalizeStyle(type, newProps?.style),
        )
      : "";
    if (newStyle !== prevStyle) {
      instance.setStyle(newStyle);
    }

    // Attach/update event handlers
    attachEventHandlers(
      instance,
      newProps,
      oldProps,
    );
  },

  hideInstance: (instance) => {
    // instance.setStyle("display: none");

    return false;
  },
  unhideInstance: (instance) => {
    // instance.setStyle("display: block");
    return false;
  },

  maySuspendCommit: () => false,

  preloadInstance: noop(null),
  startSuspendingCommit: noop(),
  suspendInstance: noop(null),
  waitForCommitToBeReady: () => null,
});

export const reconciler = _reconciler;
