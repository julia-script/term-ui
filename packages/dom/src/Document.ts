import type { Module } from "@term-ui/core/node";
import {
  DEFAULT_CURSOR,
  cursorShapeByInt,
} from "@term-ui/shared/cmd/cursor-shape";
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
import { TextElement } from "./TextElement";
import { Tree } from "./Tree";
import type {
  DocumentOptions,
  RenderingSize,
  Size,
} from "./types";
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
  private nodes: Map<
    number,
    Element | TextElement
  > = new Map();
  private state = {
    hovered: 0,
    cursorShape: DEFAULT_CURSOR,
    clicked: null as number | null,
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
    }: Partial<DocumentOptions> = {},
  ) {
    this.onPaintRequest = onPaintRequest;
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
  private onInput = (event: InputEvent) => {
    // debug.log(event);
    if (
      this.exitOnCtrlC &&
      event.kind === "key"
    ) {
      if (event.key === "c" && event.ctrl) {
        this.dispose();
        process.exit(0);
      }
    }
    if (event.kind === "mouse") {
      this.emitCursorEvents(event);
    }
    if (this.paintRequested) {
      this.paintRequested = false;
      this.paint();
    }
  };

  private emitCursorEvents = (
    event: Extract<InputEvent, { kind: "mouse" }>,
  ) => {
    if (
      event.action === "release" &&
      this.state.clicked !== null
    ) {
      const clickedNode = this.nodes.get(
        this.state.clicked,
      );
      clickedNode?.emitEvent({
        kind: "mouse-up",
        target: clickedNode as Element,
        document: this,
        x: event.x,
        y: event.y,
      });
      this.state.clicked = null;
      return;
    }
    const hovered = this.renderer.getNodeAt(
      event.x,
      event.y,
    );

    const currentNode = this.nodes.get(hovered);

    if (!currentNode) {
      throw new Error("Current node not found");
    }
    if (event.action === "press") {
      this.state.clicked = currentNode.id;
      currentNode.emitEvent({
        kind: "mouse-down",
        target: currentNode as Element,
        document: this,
        x: event.x,
        y: event.y,
      });
      currentNode.emitEvent({
        kind: "click",
        target: currentNode as Element,
        document: this,
        x: event.x,
        y: event.y,
      });

      return;
    }
    let defaultPrevented = false;
    const preventDefault = () => {
      defaultPrevented = true;
    };

    if (event.action === "wheel_up") {
      currentNode.emitEvent({
        kind: "scroll",
        target: currentNode as Element,
        document: this,
        deltaX: 0,
        deltaY: 1,
        preventDefault,
      });
      if (defaultPrevented) return;
      if (currentNode instanceof Element) {
        currentNode.scrollTop -= 1;
        this.requestPaint();
      }
      return;
    }
    if (event.action === "wheel_down") {
      currentNode.emitEvent({
        kind: "scroll",
        target: currentNode as Element,
        document: this,
        deltaX: 0,
        deltaY: -1,
        preventDefault,
      });
      if (defaultPrevented) return;
      if (currentNode instanceof Element) {
        currentNode.scrollTop += 1;
        this.requestPaint();
      }
      return;
    }
    if (event.action === "wheel_left") {
      currentNode.emitEvent({
        kind: "scroll",
        target: currentNode as Element,
        document: this,
        deltaX: -1,
        deltaY: 0,
        preventDefault,
      });
      if (defaultPrevented) return;
      if (currentNode instanceof Element) {
        currentNode.scrollLeft -= 1;
        this.requestPaint();
      }
      return;
    }
    if (event.action === "wheel_right") {
      currentNode.emitEvent({
        kind: "scroll",
        target: currentNode as Element,
        document: this,
        deltaX: 1,
        deltaY: 0,
        preventDefault,
      });
      if (defaultPrevented) return;
      if (currentNode instanceof Element) {
        currentNode.scrollLeft += 1;
        this.requestPaint();
      }
      return;
    }
    currentNode.emitEvent({
      kind: "mouse-move",
      target: currentNode as Element,
      document: this,
      x: event.x,
      y: event.y,
    });
    if (hovered === this.state.hovered) return;
    const oldHovered = this.nodes.get(
      this.state.hovered,
    );
    this.state.hovered = hovered;
    if (!oldHovered) {
      throw new Error(
        "Old hovered node not found",
      );
    }
    oldHovered.emitEvent({
      kind: "mouse-leave",
      target: oldHovered as Element,
      document: this,
    });

    const cursorShapeInt =
      this.tree.module.Tree_getNodeCursorStyle(
        this.tree.ptr,
        currentNode.id,
      );
    if (
      cursorShapeInt !== this.state.cursorShape &&
      this.writeStream
    ) {
      this.writeStream.write(
        // cursorShape(''),
        cursorShapeByInt(cursorShapeInt),
      );
      this.state.cursorShape = cursorShapeInt;
    }
    currentNode.emitEvent({
      kind: "mouse-enter",
      target: currentNode as Element,
      document: this,
    });
  };
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
    this.pushSequence(
      sequences.HIDE_CURSOR,
      sequences.SHOW_CURSOR,
    );
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
    this.tree.computeLayout(width, height);
  };

  paint = (
    clear = this.clearScreenBeforePaint,
  ) => {
    this.renderer.renderToStdout(
      this.tree,
      clear,
    );
  };
  render = (
    clear = this.clearScreenBeforePaint,
  ) => {
    this.computeLayout();
    this.paint(clear);
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
  requestPaint = () => {
    this.onPaintRequest();
  };
}
