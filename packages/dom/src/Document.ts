import * as inspector from "node:inspector/promises";
import { inspect } from "node:util";
import { HitTestFilter } from "@term-ui/core/constants";
import type { Module } from "@term-ui/core/node";
import { DEFAULT_CURSOR } from "@term-ui/shared/cmd/cursor-shape";
import { kittyKeyboardProtocol } from "@term-ui/shared/cmd/kitty-keyboard-protocol";
import * as sequences from "@term-ui/shared/cmd/sequences";
import type { ReadStream } from "@term-ui/shared/types";
import type { WriteStream } from "@term-ui/shared/types";
import { Element } from "./Element";
import {
  type InputEvent,
  InputManager,
} from "./InputManager";
import { Renderer } from "./Renderer";
import { Selection } from "./Selection";
import { TextElement } from "./TextElement";
import { Tree } from "./Tree";
import type {
  DOMEventByType,
  EventTarget,
  ScrollEvent,
  WheelEvent,
} from "./types";
// import {
//   MouseEventHandler,
//   type RawMouseInput,
// } from "./handlers/MouseEventHandler";
import type {
  DOMEvent,
  DocumentOptions,
  MouseEvent,
  RenderingSize,
  Size,
} from "./types";
const noop = () => {};
import type { KeyboardEvent } from "./types";

const resolvePercentage = (
  size:
    | number
    | "min-content"
    | "max-content"
    | `${number}%`,
  definite: number,
): number | "min-content" | "max-content" => {
  if (typeof size === "number") {
    return size;
  }
  if (size.endsWith("%")) {
    return (
      (Number.parseFloat(size) / 100) * definite
    );
  }
  return size as "min-content" | "max-content";
};



// session")
const log = (...args: unknown[]) => {
  let str = "";
  for (const arg of args) {
    if (typeof arg === "string") {
      str += `${arg} `;
    } else {
      str += `${inspect(arg, {
        colors: true,
        depth: 10,
      })} `;
    }
  }
  // client.request("console", {
  //   level: "log",
  //   scope: "dom",
  //   args: [str],
  //   trace: {
  //     message: "",
  //     frames: [],
  //   },
  // });
};

// await session.post("Console.enable");
// {"method":"Console.messageAdded","params":{"message":{"source":"console-api","level":"log","text":"connected to devtools","url":"file:///Users/juliaortiz/Documents/dev.nosync/cpp/packages/dom/dist/Document.js","line":43,"column":9}}}
// session.on("Console.messageAdded", (event) => {
//   const { message } = event.params;

//   const {
//     url,
//     line,
//     column,
//     text,
//     source,
//     level,
//   } = message;

//   if (level === "log" || level === "info") {
//     client.request("console", {
//       level,
//       scope: "dom",
//       args: [text],
//       trace: {
//         message: "",
//         frames: [
//           {
//             column: column ?? null,
//             lineNumber: line ?? null,
//             file: url?.toString() ?? null,
//             methodName: null,
//             arguments: [],
//             isTerm: false,
//           },
//         ],
//       },
//     });
//     return;
//   }
//   if (level === "warning") {
//     client.request("console", {
//       level: "warn",
//       scope: "dom",
//       args: [text],
//       trace: {
//         message: "",
//         frames: [
//           {
//             column: column ?? null,
//             lineNumber: line ?? null,
//             file: url?.toString() ?? null,
//             methodName: null,
//             arguments: [],
//             isTerm: false,
//           },
//         ],
//       },
//     });
//     return;
//   }
//   if (level === "error") {
//     client.request("console", {
//       level,
//       scope: "dom",
//       args: [],
//       trace: parseTrace(text),
//     });
//     return;
//   }
// });
// console.warn("connected to devtools", 2, 3, {
//   a: 4,
// });

export class Document {
  module: Module;
  tree: Tree;
  root: Element;
  viewportSize: Size = {
    width: 0,
    height: 0,
  };
  renderingSize: RenderingSize;
  writeStream: WriteStream;
  readStream: ReadStream;
  renderer: Renderer;
  inputManager?: InputManager;
  terminal = {
    supportsKittyKeyboardProtocol: false,
    kittyKeyboardProtocolStatus: 0,
  };
  reportLeaksOnExit: boolean;
  clearScreenBeforePaint: boolean;
  enableInputs: boolean;
  exitOnCtrlC: boolean;
  enableAlternateScreen: boolean;
  selection: Selection | null = null;
  listeners: Map<
    DOMEvent["type"],
    Set<(event: DOMEvent) => void>
  > = new Map();

  // New event system
  private nodes: Map<
    number,
    Element | TextElement
  > = new Map();
  private state = {
    scrollingElementId: null as number | null,
    activeElementId: 1, // root element
    cursorShape: DEFAULT_CURSOR,
    hoveredElements: new Set<number>(),
    activeMouseButtons: new Set<
      MouseEvent["button"]
    >(),
    isDragging: false,
  };

  private cleanups: ((this: Document) => void)[] =
    [];

  private onPaintRequest: () => void;
  private paintRequested = false;
  constructor(
    module: Module,
    {
      writeStream,
      readStream,
      size = {
        width: "100%",
        height: "100%",
      },
      clearScreenBeforePaint = true,
      reportLeaksOnExit = false,
      enableInputs = true,
      exitOnCtrlC = true,
      enableAlternateScreen = true,
      onPaintRequest = () => {
        this.paintRequested = true;
      },
      wrapInputDispatch,
    }: Partial<DocumentOptions> = {},
  ) {
    this.onPaintRequest = onPaintRequest;
    this.wrapInputDispatch = wrapInputDispatch;
    this.clearScreenBeforePaint =
      clearScreenBeforePaint;
    this.reportLeaksOnExit = reportLeaksOnExit;
    this.exitOnCtrlC = exitOnCtrlC;
    this.enableInputs = enableInputs;

    this.enableAlternateScreen =
      enableAlternateScreen;
    this.module = module;
    this.writeStream =
      writeStream ?? process.stdout;
    this.readStream = readStream ?? process.stdin;

    this.tree = Tree.init(module);

    this.pushCleanup(() => this.tree.dispose());

    this.initInputs();

    this.renderer = Renderer.init(
      module,
      this.writeStream,
    );
    this.pushCleanup(() =>
      this.renderer.dispose(),
    );

    this.root = Element.fromNode(
      this,
      this.tree.createNode("").id,
    );

    this.renderingSize = size ?? {
      width: "100%",
      height: "max-content",
    };
    this.viewportSize = {
      width: this.writeStream.columns,
      height: this.writeStream.rows,
    };

    // Initialize event system
    // this.inputState = new InputState();
    // this.mouseEventHandler =
    //   new MouseEventHandler(this.inputState);
    // this.keyboardEventHandler =
    //   new KeyboardEventHandler(this.inputState);

    process.on("resize", this.onResize);
    this.pushCleanup(() =>
      process.off("resize", this.onResize),
    );
    if (process) {
      process.on("exit", this.dispose);
      this.pushCleanup(() =>
        process.off("exit", this.dispose),
      );
    }
  }
  private pushSequence = (
    sequence: string,
    cleanupSequence?: string,
  ) => {
    if (cleanupSequence) {
      this.pushCleanup(() =>
        this.writeStream.write(cleanupSequence),
      );
    }
    this.writeStream.write(sequence);
  };
  private pushCleanup = (
    cleanup: (this: Document) => void,
  ) => {
    this.cleanups.push(cleanup.bind(this));
  };
  private wrapInputDispatch?: (
    event: InputEvent,
    dispatch: () => void,
  ) => void;
  private onInput = (event: InputEvent) => {
    const dispatch = () => {
      if (event.kind === "key") {
        this.emitKeyEvents(event);
      }
      if (
        event.kind === "mouse" ||
        event.kind === "mouse-legacy"
      ) {
        this.emitMouseEvents(event);
      }
    };
    if (this.wrapInputDispatch) {
      this.wrapInputDispatch(event, dispatch);
    } else {
      dispatch();
    }
  };

  // private getEventTarget = (
  //   x: number,
  //   y: number,
  // ): Element | TextElement | null => {
  //   const hitTestResult = this.renderer.hitTest(
  //     this.tree,
  //     x,
  //     y,
  //     HitTestFilter.BOX |
  //       HitTestFilter.TEXT_FRAGMENT |
  //       HitTestFilter.LINE_BOX,
  //   );

  //   if (!hitTestResult) return null;
  //   return (
  //     this.nodes.get(hitTestResult.id) || null
  //   );
  // };

  // private dispatchEvent = (event: DOMEvent) => {
  //   const target = event.target;
  //   if (!target) return;

  //   // Map new event types to old event system
  //   let eventKind: string;
  //   switch (event.type) {
  //     case "mousedown":
  //       eventKind = "mousedown";
  //       break;
  //     case "mouseup":
  //       eventKind = "mouseup";
  //       break;
  //     case "mousemove":
  //       eventKind = "mousemove";
  //       break;
  //     case "click":
  //       eventKind = "click";
  //       break;
  //     case "dblclick":
  //       eventKind = "double-click";
  //       break;
  //     case "keydown":
  //       eventKind = "keydown";
  //       break;
  //     case "keyup":
  //       eventKind = "keyup";
  //       break;
  //     case "keypress":
  //       eventKind = "keypress";
  //       break;
  //     default:
  //       return;
  //   }

  //   // Handle mouse events

  //   // Handle selection on mousedown
  //   if (event.type === "mousedown") {
  //     const bp = this.caretPositionFromPoint(
  //       event.x,
  //       event.y,
  //     );
  //     if (bp) {
  //       this.createSelection({
  //         node: bp.node,
  //         offset: bp.offset,
  //       });
  //       this.requestPaint();
  //     }
  //   }

  //   // Handle selection drag on mousemove
  //   if (
  //     event.type === "mousemove" &&
  //     this.inputState.isDragging()
  //   ) {
  //     const selection = this.selection;
  //     if (selection) {
  //       const bp = this.caretPositionFromPoint(
  //         event.x,
  //         event.y,
  //       );
  //       if (bp) {
  //         selection.setFocus(bp.node, bp.offset);
  //         this.requestPaint();
  //       }
  //     }
  //   }

  //   // Update cursor shape on hover
  //   if (event.type === "mousemove") {
  //     const cursorShapeInt =
  //       this.tree.module.Tree_getNodeCursorStyle(
  //         this.tree.ptr,
  //         target.id,
  //       );
  //     if (
  //       cursorShapeInt !==
  //         this.state.cursorShape &&
  //       this.writeStream
  //     ) {
  //       this.writeStream.write(
  //         cursorShapeByInt(cursorShapeInt),
  //       );
  //       this.state.cursorShape = cursorShapeInt;
  //     }
  //   }

  //   if (
  //     event.type === "mousedown" ||
  //     event.type === "mouseup" ||
  //     event.type === "mousemove" ||
  //     event.type === "click" ||
  //     event.type === "dblclick"
  //   ) {
  //     // Emit event on target
  //     target.emitEvent({
  //       type: event.type,
  //       target: target,
  //       document: this,
  //       x: event.x,
  //       y: event.y,
  //       preventDefault:
  //         event.preventDefault.bind(event),
  //     });
  //   }
  //   // Handle keyboard events

  //   if ("key" in event) {
  //     const keyEvent = event as KeyboardEvent;
  //     target.emitEvent({
  //       type: event.type,
  //       target: target,
  //       document: this,
  //       key: keyEvent.key,
  //       codepoint: keyEvent.charCode || 0,
  //       text: keyEvent.key || "",
  //       shift: keyEvent.shiftKey,
  //       ctrl: keyEvent.ctrlKey,
  //       alt: keyEvent.altKey,
  //       super: keyEvent.metaKey,
  //       meta: keyEvent.metaKey,
  //       repeat: keyEvent.repeat || false,
  //       preventDefault:
  //         event.preventDefault.bind(event),
  //     });

  //     // Handle default keyboard behavior if not prevented
  //     if (!event.defaultPrevented) {
  //       this.handleDefaultKeyBehavior(
  //         event,
  //         target,
  //       );
  //     }
  //   }
  // };

  // private handleScrollWheel = (
  //   event: Extract<InputEvent, { kind: "mouse" }>,
  //   target: Element | TextElement,
  // ) => {
  //   let defaultPrevented = false;
  //   const preventDefault = () => {
  //     defaultPrevented = true;
  //   };

  //   let deltaX = 0;
  //   let deltaY = 0;

  //   switch (event.action) {
  //     case "wheel_up":
  //       deltaY = 1;
  //       break;
  //     case "wheel_down":
  //       deltaY = -1;
  //       break;
  //     case "wheel_left":
  //       deltaX = -1;
  //       break;
  //     case "wheel_right":
  //       deltaX = 1;
  //       break;
  //     default:
  //       return;
  //   }

  //   target.emitEvent({
  //     kind: "scroll",
  //     target: target as Element,
  //     document: this,
  //     deltaX,
  //     deltaY,
  //     preventDefault,
  //   });

  //   if (
  //     !defaultPrevented &&
  //     target instanceof Element
  //   ) {
  //     if (deltaY !== 0) {
  //       target.scrollTop -= deltaY;
  //     }
  //     if (deltaX !== 0) {
  //       target.scrollLeft -= deltaX;
  //     }
  //     this.requestPaint();
  //   }
  // };
  private initInputs = async () => {
    if (!this.enableInputs) return;
    const inputManager = InputManager.init(
      this.tree.module,
      this.readStream,
      this.tree,
    );

    this.inputManager = inputManager;
    this.pushCleanup(() =>
      this.inputManager?.dispose(),
    );
    this.pushCleanup(
      this.inputManager?.subscribe(this.onInput),
    );

    const stdin = this.readStream;
    const stdout = this.writeStream;
    if (this.enableAlternateScreen) {
      this.pushSequence(
        sequences.ENABLE_ALTERNATE_SCREEN,
        sequences.DISABLE_ALTERNATE_SCREEN,
      );
    }
    // this.pushSequence(
    //   sequences.DISABLE_SCREEN_WRAP_MODE,
    //   sequences.ENABLE_SCREEN_WRAP_MODE,
    // );
    // this.pushSequence(
    //   sequences.HIDE_CURSOR,
    //   sequences.SHOW_CURSOR,
    // );
    this.pushSequence(
      sequences.ENABLE_SGR_EXT_MODE_MOUSE,
      sequences.DISABLE_SGR_EXT_MODE_MOUSE,
    );
    this.pushSequence(
      sequences.ENABLE_ANY_EVENT_MOUSE,
      sequences.DISABLE_ANY_EVENT_MOUSE,
    );
    this.pushSequence(
      sequences.CLEAR_SCROLLBACK_BUFFER,
      sequences.CLEAR_SCROLLBACK_BUFFER,
    );

    this.readStream.setRawMode(true);
    this.pushCleanup(() =>
      this.readStream.setRawMode(false),
    );

    try {
      const kittyKeyboardProtocolStatus =
        await kittyKeyboardProtocol.query({
          readStream: stdin,
          writeStream: stdout,
        });
      this.terminal.supportsKittyKeyboardProtocol = true;
      this.pushSequence(
        kittyKeyboardProtocol.push(
          kittyKeyboardProtocol.ALL,
        ),
      );
      this.terminal.kittyKeyboardProtocolStatus =
        kittyKeyboardProtocolStatus;
    } catch (error) {
      this.terminal.supportsKittyKeyboardProtocol = false;
    }
  };
  getElement = (id: number) => {
    return this.nodes.get(id);
  };
  getOrAddElement = (id: number) => {
    const element = this.nodes.get(id);
    if (element) return element;
    const nodeKind =
      this.tree.module.Tree_getNodeKind(
        this.tree.ptr,
        id,
      );
    if (nodeKind === 1) {
      const element = Element.fromNode(this, id);
      this.addElement(element);
      return element;
    }
    const textElement = TextElement.fromNode(
      this,
      id,
    );
    this.addElement(textElement);
    return textElement;
  };
  addElement = (
    element: Element | TextElement,
  ) => {
    this.nodes.set(element.id, element);
  };
  removeElement = (
    element: Element | TextElement,
  ) => {
    this.nodes.delete(element.id);
  };
  private cleanup = () => {
    const reversed = [...this.cleanups].reverse();
    for (const cleanup of reversed) {
      cleanup.call(this);
    }
    // this.cleanupSequences();
  };
  private onResize = () => {};
  computeLayout = () => {
    this.viewportSize = {
      width: this.writeStream.columns,
      height: this.writeStream.rows,
    };
    const width = resolvePercentage(
      this.renderingSize.width,
      this.viewportSize.width,
    );
    const height = resolvePercentage(
      this.renderingSize.height,
      this.viewportSize.height,
    );

    this.tree.computeStyles();
    this.tree.buildLayoutTree();
    this.tree.computeLayout(width, height);
  };

  paint = () => {
    this.writeStream.write(sequences.HIDE_CURSOR);
    this.renderer.paint(this.tree);
    this.restoreCursor();
  };
  private restoreCursor = () => {
    if (this.selection?.isEditable()) {
      const focusPosition =
        this.module.Selection_getFocusPosition(
          this.tree.ptr,
          this.selection.id,
        );
      if (focusPosition) {
        this.writeStream.write(
          `\x1b[${focusPosition.y + 1};${focusPosition.x + 1}H${sequences.SHOW_CURSOR}${sequences.CURSOR_BLINKING_BAR}`,
        );
      }
    }
  };
  render = () => {
    this.computeLayout();
    this.paint();
  };
  dispose = () => {
    this.cleanup();
    this.module.detectLeaks();
  };
  [Symbol.dispose] = () => {
    this.dispose();
  };

  /*
   * document nodes api
   */

  createElement = (
    tag: "view" | "text",
    style?: string,
  ): Element => {
    // in the future we will have more tags
    switch (tag) {
      case "view":
        return Element.fromNode(
          this,
          this.tree.createNode(style ?? "").id,
        );
      case "text":
        return Element.fromNode(
          this,
          this.tree.createNode(
            `display: inline;${style ?? ""}`,
          ).id,
        );
      default:
        throw new Error(`Unknown tag: ${tag}`);
    }
  };

  createTextNode = (
    text: string,
  ): TextElement => {
    return TextElement.fromNode(
      this,
      this.tree.createTextNode(text).id,
    );
  };

  getElementById = (
    id: string,
  ): Element | TextElement | null => {
    const nodeId =
      this.module.Tree_getElementById(
        this.tree.ptr,
        id,
      );
    if (nodeId === -1) {
      return null;
    }

    const kind = this.module.Tree_getNodeKind(
      this.tree.ptr,
      nodeId,
    );
    if (kind === 1) {
      return Element.fromNode(this, nodeId);
    }
    if (kind === 2) {
      return TextElement.fromNode(this, nodeId);
    }
    return null;
  };

  requestPaint = () => {
    this.onPaintRequest();
  };

  createSelection = (
    start: {
      node: number;
      offset: number;
    },
    end?: {
      node: number;
      offset: number;
    },
  ) => {
    this.removeSelection();
    const ptr = this.module.Tree_createSelection(
      this.tree.ptr,
      start.node,
      start.offset,
      end?.node ?? start.node,
      end?.offset ?? start.offset,
    );
    const selection = new Selection(this, ptr);
    this.selection = selection;
    return selection;
  };
  removeSelection = () => {
    if (!this.selection) return;
    this.module.Tree_removeSelection(
      this.tree.ptr,
      this.selection.id,
    );
    this.selection = null;
  };

  caretPositionFromPoint = (
    x: number,
    y: number,
  ) => {
    try {
      return this.module.Tree_caretPositionFromPoint(
        this.tree.ptr,

        x,
        y,
      );
    } catch (e) {
      console.error(e);
      return null;
    }
  };

  // private handleDefaultKeyBehavior = (
  //   event: DOMEvent,
  //   element: Element,
  // ) => {
  //   if (!("key" in event)) return;
  //   const keyEvent = event as KeyboardEvent;
  //   // Only handle on initial press (not repeat or release)
  //   if (
  //     !keyEvent.willRelease &&
  //     keyEvent.type !== "keydown"
  //   )
  //     return;

  //   // Handle selection movement with Shift+Arrow keys
  //   if (
  //     keyEvent.shiftKey &&
  //     (keyEvent.key === "up" ||
  //       keyEvent.key === "down" ||
  //       keyEvent.key === "left" ||
  //       keyEvent.key === "right")
  //   ) {
  //     // Create selection if it doesn't exist
  //     if (!this.selection) {
  //       // Get caret position from current position or use the first position
  //       const caretPosition =
  //         this.caretPositionFromPoint(0, 0);
  //       if (caretPosition) {
  //         this.createSelection({
  //           node: caretPosition.node,
  //           offset: caretPosition.offset,
  //         });
  //       }
  //     }

  //     // If we have a selection, extend it in the direction of the arrow key
  //     if (this.selection) {
  //       // Determine direction (forward or backward)
  //       const direction: "forward" | "backward" =
  //         keyEvent.key === "down" ||
  //         keyEvent.key === "right"
  //           ? "forward"
  //           : "backward";

  //       // Use line granularity for up/down, character granularity for left/right
  //       const granularity: "character" | "line" =
  //         keyEvent.key === "up" ||
  //         keyEvent.key === "down"
  //           ? "line"
  //           : "character";

  //       // Extend the selection with the appropriate granularity and direction
  //       this.selection.extendBy(
  //         granularity,
  //         direction,
  //       );
  //       this.requestPaint();
  //       return;
  //     }
  //   }

  //   // Basic arrow key navigation (when shift is not pressed)
  //   if (
  //     !keyEvent.shiftKey &&
  //     (keyEvent.key === "up" ||
  //       keyEvent.key === "down" ||
  //       keyEvent.key === "left" ||
  //       keyEvent.key === "right")
  //   ) {
  //     // Clear any existing selection when navigating without shift
  //     if (this.selection) {
  //       this.removeSelection();
  //     }

  //     // Handle arrow key navigation
  //     if (keyEvent.key === "up") {
  //       element.scrollTop -= 1;
  //     } else if (keyEvent.key === "down") {
  //       element.scrollTop += 1;
  //     } else if (keyEvent.key === "left") {
  //       element.scrollLeft -= 1;
  //     } else if (keyEvent.key === "right") {
  //       element.scrollLeft += 1;
  //     }
  //     this.requestPaint();
  //   }
  // };
  private emitMouseEvents = (
    input: Extract<
      InputEvent,
      { kind: "mouse" | "mouse-legacy" }
    >,
  ) => {
    // Physical button state is tracked before dispatch: a release is a
    // fact, not a default action, so it must clear state even when a
    // handler calls preventDefault or the release can't name its button
    // (legacy encoding). Button-less motion also heals a missed release
    // (e.g. button let go outside the window).
    if (input.kind === "mouse") {
      if (input.action === "press") {
        this.state.activeMouseButtons.add(
          input.button,
        );
      } else if (input.action === "release") {
        this.state.activeMouseButtons.delete(
          input.button,
        );
        this.state.isDragging = false;
      } else if (
        input.action === "motion" &&
        input.button === "none"
      ) {
        this.state.activeMouseButtons.clear();
        this.state.isDragging = false;
      }
    } else {
      if (input.action.endsWith("_press")) {
        this.state.activeMouseButtons.add(
          input.action.replace(
            "_press",
            "",
          ) as MouseEvent["button"],
        );
      } else if (
        input.action.includes("release")
      ) {
        this.state.activeMouseButtons.clear();
        this.state.isDragging = false;
      }
    }
    const { x, y } = input;
    const hitTestListResult =
      this.tree.module.Tree_hitTestList(
        this.tree.ptr,
        x,
        y,
        HitTestFilter.BOX |
          HitTestFilter.TEXT_FRAGMENT,
      );
    const targets: EventTarget[] = [];

    const hoveredElements: number[] = [];
    for (const hitTestResult of hitTestListResult) {
      const node = this.nodes.get(
        hitTestResult.id,
      );

      if (node instanceof Element) {
        hoveredElements.push(node.id);
        targets.push(node);
      } else if (node instanceof TextElement) {
        // hoveredElements.push(node.id);
        const parent = node.parent;
        if (parent) {
          hoveredElements.push(parent.id);
          targets.push(parent as EventTarget);
        }
      }
    }
    targets.reverse();
    hoveredElements.reverse();
    const self = this;
    targets.push(self);

    const initialTarget = targets.at(0) ?? this;

    const event = this.createMouseEvent(
      input,
      initialTarget,
    );
    const eventTemplate: MouseEvent | WheelEvent =
      {
        ...event,
      };

    const notVisited = new Set(
      this.state.hoveredElements,
    );
    if (event.type === "mousemove") {
      const previousHoveredElements =
        this.state.hoveredElements;
      // emit mouseenter and mouseleave events

      for (const hoveredElementId of hoveredElements) {
        const hoveredElement = this.nodes.get(
          hoveredElementId,
        ) as Element;
        // elements currently hovered that were not hovered before
        if (
          !previousHoveredElements.has(
            hoveredElementId,
          )
        ) {
          notVisited.delete(hoveredElementId);
          const enterEvent: MouseEvent = {
            ...eventTemplate,
            type: "mouseenter",
            target: hoveredElement,
            currentTarget: hoveredElement,
            preventDefault: () => {
              enterEvent.defaultPrevented = true;
            },
            stopPropagation: () => {
              enterEvent.bubbles = false;
            },
          };

          hoveredElement.emitEvent(enterEvent);
        }
      }
    }
    this.state.hoveredElements = new Set(
      hoveredElements,
    );

    for (const target of targets) {
      event.currentTarget = target;
      target.emitEvent(event);
      if (event.bubbles === false) {
        break;
      }
    }
    if (!event.defaultPrevented) {
      this.handleDefaultMouseBehavior(event);
    }
    if (event.type === "mousemove") {
      // nodes that are not visited but were hovered before
      for (const hoveredElementId of notVisited) {
        const hoveredElement = this.nodes.get(
          hoveredElementId,
        ) as Element;
        const leaveEvent: MouseEvent = {
          ...eventTemplate,
          type: "mouseleave",
          target: hoveredElement,
          currentTarget: hoveredElement,
          preventDefault: () => {
            leaveEvent.defaultPrevented = true;
          },
          stopPropagation: () => {
            leaveEvent.bubbles = false;
          },
        };
        hoveredElement.emitEvent(leaveEvent);
      }
      if (!event.defaultPrevented) {
        this.handleDefaultMouseBehavior(event);
      }
    }

    // Emit click event after mouseup
    if (event.type === "mouseup") {
      const clickEvent: MouseEvent = {
        ...eventTemplate,
        type: "click",
        bubbles: true,
        cancelable: true,
        defaultPrevented: false,

        preventDefault: () => {
          clickEvent.defaultPrevented = true;
        },
        stopPropagation: () => {
          clickEvent.bubbles = false;
        },
      };

      // Emit click event through the same targets
      for (const target of targets) {
        clickEvent.currentTarget = target;
        target.emitEvent(clickEvent);
        if (clickEvent.bubbles === false) {
          break;
        }
      }
      if (!clickEvent.defaultPrevented) {
        this.handleDefaultMouseBehavior(
          clickEvent,
        );
      }
    }
    // scroll event is not cancelable, but preventing the default behavior from the wheel event prevents the scroll event too
    if (
      event.type === "wheel" &&
      !event.defaultPrevented
    ) {
      // const scrollEvent: ScrollEvent = {
      //   type: "scroll",
      //   target: event.target,
      //   cancelable: false,
      //   preventDefault: noop,
      //   stopPropagation: noop,
      //   currentTarget: null,
      // };
      // const scrollDirection =
      //   event.deltaY !== 0 ? 1 : 0;
      // const offset =
      //   scrollDirection === 1
      //     ? event.deltaY
      //     : event.deltaX;

      const scrollContainer =
        this.getScrollContainer(
          targets,
          event.deltaX,
          event.deltaY,
        );

      if (!scrollContainer) return;
      // log(
      //   "scrollContainer",
      //   scrollContainer.id,
      //   scrollContainer.scrollHeight,
      //   scrollContainer.clientHeight,
      //   scrollContainer.scrollTop,
      //   scrollContainer.scrollTopMax,
      // );
      this.setScrollingElement(
        scrollContainer.id,
      );
      scrollContainer.scrollBy(
        event.deltaX,
        event.deltaY,
      );
    }
  };
  private scrollingElementTimeout: NodeJS.Timeout | null =
    null;
  private setScrollingElement = (
    elementId: number,
  ) => {
    if (this.scrollingElementTimeout) {
      clearTimeout(this.scrollingElementTimeout);
    }
    this.state.scrollingElementId = elementId;
    this.scrollingElementTimeout = setTimeout(
      () => {
        this.state.scrollingElementId = null;
      },
      100,
    );
  };
  private getScrollContainer = (
    targets: EventTarget[],
    deltaX: number,
    deltaY: number,
  ) => {
    if ((deltaY | deltaX) === 0) return null;
    const scrollDirection = deltaY !== 0 ? 1 : 0;
    const offset =
      scrollDirection === 1 ? deltaY : deltaX;

    // scroll latching: a recent scroll keeps targeting the same element,
    // but only while the pointer is still over it AND it can still scroll
    // in this direction — otherwise re-resolve (pane switch / edge chain)
    if (this.state.scrollingElementId !== null) {
      const latched = this.getOrAddElement(
        this.state.scrollingElementId,
      );
      if (
        targets.includes(
          latched as EventTarget,
        ) &&
        this.tree.module.Node_canScroll(
          this.tree.ptr,
          latched.id,
          scrollDirection,
          offset,
        )
      ) {
        return latched as Element;
      }
    }

    for (const target of targets) {
      if (target instanceof Element) {

        if (
          this.tree.module.Node_canScroll(
            this.tree.ptr,
            target.id,
            scrollDirection,
            offset,
          )
        ) {
          return target;
        }
      }
    }
    return null;
  };

  createMouseEvent = (
    input: Extract<
      InputEvent,
      { kind: "mouse" | "mouse-legacy" }
    >,
    initialTarget: EventTarget,
  ) => {
    if (input.kind === "mouse") {
      let type: MouseEvent["type"] = "mousemove";
      if (input.action === "press") {
        type = "mousedown";
      } else if (input.action === "release") {
        type = "mouseup";
      } else if (input.action === "motion") {
        type = "mousemove";
      }

      const event: MouseEvent = {
        type,
        target: initialTarget,
        currentTarget: initialTarget,
        bubbles: true,
        defaultPrevented: false,
        button: input.button,
        clientX: input.x,
        clientY: input.y,
        altKey: input.alt,
        ctrlKey: input.ctrl,
        shiftKey: input.shift,
        metaKey: input.super,
        cancelable: true,
        preventDefault: () => {
          event.defaultPrevented = true;
        },
        stopPropagation: () => {
          event.bubbles = false;
        },
      };
      if (input.action.startsWith("wheel")) {
        const wheelEvent: WheelEvent = {
          ...event,
          type: "wheel",
          deltaX:
            input.action === "wheel_left"
              ? -1
              : input.action === "wheel_right"
                ? 1
                : 0,
          deltaY:
            input.action === "wheel_up"
              ? -1
              : input.action === "wheel_down"
                ? 1
                : 0,
          // own closures: the spread copies the base event's, which would
          // flag the wrong object and make preventDefault a no-op
          preventDefault: () => {
            wheelEvent.defaultPrevented = true;
          },
          stopPropagation: () => {
            wheelEvent.bubbles = false;
          },
        };
        return wheelEvent;
      }
      return event;
    }

    let type: MouseEvent["type"] = "mousemove";
    let button = "none";

    // Map legacy mouse actions to event types and buttons
    switch (input.action) {
      case "left_press":
        type = "mousedown";
        button = "left";
        break;
      case "middle_press":
        type = "mousedown";
        button = "middle";
        break;
      case "right_press":
        type = "mousedown";
        button = "right";
        break;
      case "release":
        type = "mouseup";
        button = "none"; // Legacy doesn't specify which button was released
        break;
      default:
        // For wheel events, we'll handle them as wheel events
        if (input.action.startsWith("wheel")) {
          const wheelEvent: WheelEvent = {
            type: "wheel",
            target: initialTarget,
            currentTarget: initialTarget,
            bubbles: true,
            defaultPrevented: false,
            button: "wheel",
            clientX: input.x,
            clientY: input.y,
            altKey: input.alt,
            ctrlKey: input.ctrl,
            shiftKey: input.shift,
            metaKey: input.super,
            deltaX:
              input.action === "wheel_tilt_left"
                ? -1
                : input.action ===
                    "wheel_tilt_right"
                  ? 1
                  : 0,
            deltaY:
              input.action === "wheel_forward"
                ? -1
                : input.action === "wheel_back"
                  ? 1
                  : 0,
            cancelable: true,
            preventDefault: () => {
              wheelEvent.defaultPrevented = true;
            },
            stopPropagation: () => {
              wheelEvent.bubbles = false;
            },
          };
          return wheelEvent;
        }
        break;
    }

    const event: MouseEvent = {
      type,
      target: initialTarget,
      currentTarget: initialTarget,
      bubbles: true,
      defaultPrevented: false,
      button,
      clientX: input.x,
      clientY: input.y,
      altKey: input.alt,
      ctrlKey: input.ctrl,
      shiftKey: input.shift,
      metaKey: input.super,
      cancelable: true,
      preventDefault: () => {
        event.defaultPrevented = true;
      },
      stopPropagation: () => {
        event.bubbles = false;
      },
    };

    return event;
  };
  private emitKeyEvents = (
    input: Extract<InputEvent, { kind: "key" }>,
  ) => {
    // log(input);
    const type =
      input.action === "release"
        ? "keyup"
        : "keydown";

    const target = this.nodes.get(
      this.state.activeElementId,
    );
    // log(input);

    if (!target) {
      return;
    }

    if (target instanceof TextElement) {
      throw new Error(
        "TextElement is not a valid target",
      );
    }
    // let currentTarget = target;
    const event: KeyboardEvent = {
      target,
      currentTarget: target,
      type,
      key: input.key || "",
      code: input.text || input.key || "",
      charCode: input.codepoint,
      bubbles: true,
      defaultPrevented: false,
      text: input.text,
      cancelable: true,
      preventDefault: () => {
        event.defaultPrevented = true;
      },
      stopPropagation: () => {
        event.bubbles = false;
      },
      shiftKey: input.shift,
      ctrlKey: input.ctrl,
      altKey: input.alt,
      metaKey: input.super,
      repeat: input.action === "repeat",
    };

    while (true) {
      if (
        event.currentTarget instanceof Document
      ) {
        event.currentTarget.emitEvent(event);
        break;
      }
      event.currentTarget.emitEvent(event);
      if (event.bubbles === false) {
        break;
      }
      const parent =
        event.currentTarget.parent || this;
      event.currentTarget = parent;
    }

    if (event.defaultPrevented) {
      return;
    }

    this.handleDefaultKeyBehavior(event);
  };

  emitEvent = (event: DOMEvent) => {
    const set = this.listeners.get(event.type);
    if (set) {
      for (const listener of set) {
        listener(event);
      }
    }
  };

  private handleDefaultKeyBehavior = (
    event: KeyboardEvent,
  ) => {
    if (
      event.type === "keydown" &&
      event.key === "c" &&
      event.ctrlKey
    ) {
      this.dispose();
      process.exit(0);
    }
    if (event.type === "keydown") {
      if (event.key === "delete") {
        if (!this.selection) {
          return;
        }
        // forward-delete: a collapsed caret removes the next character
        if (this.selection.isCollapsed()) {
          this.selection.modify(
            "extend",
            "forward",
            "character",
          );
        }
        const anchor = this.selection.getAnchor();
        if (!anchor) {
          return;
        }
        const anchorNode = this.getOrAddElement(
          anchor.node,
        );
        if (!anchorNode.isEditable()) {
          return;
        }
        this.selection.deleteFromDocument();
        this.requestPaint();
        return;
      }
      if (event.key === "backspace") {
        if (!this.selection) {
          return;
        }

        if (this.selection.isCollapsed()) {
          this.selection.modify(
            "extend",
            "backward",
            "character",
          );
        }
        const anchor = this.selection.getAnchor();
        if (!anchor) {
          return;
        }
        const anchorNode = this.getOrAddElement(
          anchor.node,
        );
        if (!anchorNode.isEditable()) {
          return;
        }
        this.selection.deleteFromDocument();
        this.requestPaint();
        return;
      }
      if (
        event.key === "page_up" ||
        event.key === "page_down"
      ) {
        const container =
          this.findActiveScrollContainer();
        if (container) {
          const page = container.clientHeight;
          container.scrollBy(
            0,
            event.key === "page_down"
              ? page
              : -page,
          );
        }
        return;
      }
      if (this.selection) {
        // shift extends, plain movement collapses (browser arrow-key behavior)
        const alter = event.shiftKey
          ? ("extend" as const)
          : ("move" as const);
        // meta jumps to the line boundary, alt/ctrl moves by word
        const horizontalGranularity =
          event.metaKey
            ? ("lineboundary" as const)
            : event.altKey || event.ctrlKey
              ? ("word" as const)
              : ("character" as const);
        switch (event.key) {
          case "down":
            this.selection.modify(
              alter,
              "forward",
              "line",
            );
            this.scrollCaretIntoView();
            this.requestPaint();
            break;
          case "up":
            this.selection.modify(
              alter,
              "backward",
              "line",
            );
            this.scrollCaretIntoView();
            this.requestPaint();
            break;
          case "right":
            this.selection.modify(
              alter,
              "forward",
              horizontalGranularity,
            );
            this.scrollCaretIntoView();
            this.requestPaint();
            break;
          case "left":
            this.selection.modify(
              alter,
              "backward",
              horizontalGranularity,
            );
            this.scrollCaretIntoView();
            this.requestPaint();
            break;
          default: {
            // typing inserts only inside editable regions, and only for
            // keys that produce text
            if (!event.text) {
              return;
            }
            const anchor =
              this.selection.getAnchor();
            const focus =
              this.selection.getFocus();
            if (anchor.node === focus.node) {
              const anchorNode =
                this.getOrAddElement(anchor.node);
              if (
                anchorNode instanceof TextElement &&
                anchorNode.isEditable()
              ) {
                // range.deleteContents();
                anchorNode.insertData(
                  anchor.offset,
                  event.text,
                );

                // range.setEnd(focus.node, focus.offset + event.text.length);
                this.selection.setFocus(
                  anchor.node,
                  anchor.offset +
                    event.text.length,
                );
                this.selection.collapseToEnd();
                this.scrollCaretIntoView();
                this.requestPaint();
                return;
              }
              return;
            }
          }
        }
      }
    }
  };

  /** After keyboard-driven selection changes, scroll ancestors the minimal
   * amount so the caret is visible (innermost first). Not applied to mouse
   * placement: the click already happened at a visible point. */
  scrollCaretIntoView = () => {
    const selection = this.selection;
    if (!selection) return;
    const focus = selection.getFocus();
    if (!focus) return;
    let el: Element | TextElement | undefined =
      this.getOrAddElement(focus.node);
    while (el) {
      if (
        el instanceof Element &&
        el.scrollTopMax > 0
      ) {
        // fresh geometry for this level
        this.computeLayout();
        this.paint();
        const caret =
          this.module.Tree_getBoundaryPointPosition(
            this.tree.ptr,
            focus.node,
            focus.offset,
          );
        const rect = el.getBoundingClientRect();
        // ponytail: border widths aren't exposed to JS; assume the
        // vertical chrome is split evenly (true for uniform borders)
        const chrome =
          (rect.height - el.clientHeight) / 2;
        const top = rect.y + chrome;
        const bottom = top + el.clientHeight;
        if (caret.y < top) {
          el.scrollBy(0, caret.y - top);
        } else if (caret.y >= bottom) {
          el.scrollBy(0, caret.y - bottom + 1);
        }
      }
      el = el.parent ?? undefined;
    }
  };

  /** The scroll container PgUp/PgDn acts on: nearest scrollable ancestor
   * of the selection anchor, else the deepest hovered scrollable. */
  private findActiveScrollContainer = ():
    | Element
    | null => {
    const isScrollable = (el: Element) =>
      el.scrollTopMax > 0 ||
      el.scrollLeftMax > 0;
    const anchor = this.selection?.getAnchor();
    if (anchor) {
      let el: Element | TextElement | undefined =
        this.getOrAddElement(anchor.node);
      while (el) {
        if (
          el instanceof Element &&
          isScrollable(el)
        ) {
          return el;
        }
        el = el.parent ?? undefined;
      }
    }
    let deepest: Element | null = null;
    for (const id of this.state
      .hoveredElements) {
      const el = this.nodes.get(id);
      if (
        el instanceof Element &&
        isScrollable(el)
      ) {
        deepest = el;
      }
    }
    return deepest;
  };

  private handleDefaultMouseBehavior = (
    event: MouseEvent | WheelEvent,
  ) => {
    if (event.type === "mousedown") {
      if (event.button !== "left") {
        return;
      }
      const bp = this.caretPositionFromPoint(
        event.clientX,
        event.clientY,
      );
      if (bp) {
        this.createSelection(bp);
        // arm drag-select only when the press actually placed a caret
        this.state.isDragging = true;
        this.requestPaint();
      }
      return;
    }
    if (event.type === "mouseup") {
      this.state.isDragging = false;
      return;
    }
    if (event.type === "mousemove") {
      if (
        this.state.isDragging &&
        this.state.activeMouseButtons.has(
          "left",
        ) &&
        this.selection
      ) {
        const bp = this.caretPositionFromPoint(
          event.clientX,
          event.clientY,
        );
        const selection = this.selection;
        if (bp && selection) {
          selection.setFocus(bp.node, bp.offset);
          this.requestPaint();
        }
      }
    }
  };

  addEventListener = <
    const K extends DOMEvent["type"],
  >(
    event: K,
    listener: (event: DOMEventByType<K>) => void,
  ) => {
    const set =
      this.listeners.get(event) ?? new Set();
    set.add(
      listener as (event: DOMEvent) => void,
    );
    this.listeners.set(event, set);
  };
  removeEventListener = <
    K extends DOMEvent["type"],
  >(
    event: K,
    listener: (
      event: Extract<DOMEvent, { type: K }>,
    ) => void,
  ) => {
    const set = this.listeners.get(event);
    set?.delete(
      listener as (event: DOMEvent) => void,
    );
  };
  [Symbol.for("nodejs.util.inspect.custom")]() {
    // @ts-expect-error
    const rootString = this.root[Symbol.for("nodejs.util.inspect.custom")]();
    let rootStringLines = "";
    for (const line of rootString.split("\n")) {
      rootStringLines += `  ${line}\n`;
    }
    return `<Document tree={@${this.tree.ptr.toString(16)}}>\n${rootStringLines}</Document>`;
  }
}
