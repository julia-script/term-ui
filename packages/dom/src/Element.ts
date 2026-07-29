import { assert } from "@term-ui/shared/assert";
import type { Document } from "./Document";
import { Node } from "./Node";
import { TextElement } from "./TextElement";

import type { DOMEvent, DOMEventByType } from "./types";

export type ScrollOptions = {
  top?: number;
  left?: number;
  behavior?: "smooth" | "instant" | "auto";
}


export class Element extends Node {
  listeners: Map<
    DOMEvent["type"],
    Set<(event: DOMEvent) => void>
  > = new Map();
  constructor(
    private document: Document,
    id: number,
  ) {
    if (document.getElement(id)) {
      throw new Error("Node already exists");
    }
    super(document.tree, id);
    document.addElement(this);
    this.scrollBy = this.scrollBy.bind(this);
    this.scrollTo = this.scrollTo.bind(this);
  }
  get clientWidth() {
    this.assertNotDisposed();
    return this.tree.module.Node_getClientWidth(
      this.tree.ptr,
      this.id,
    );
  }
  get clientHeight() {
    this.assertNotDisposed();
    return this.tree.module.Node_getClientHeight(
      this.tree.ptr,
      this.id,
    );
  }
  get scrollWidth() {
    this.assertNotDisposed();
    return this.tree.module.Node_getScrollWidth(
      this.tree.ptr,
      this.id,
    );
  }
  get scrollHeight() {
    this.assertNotDisposed();
    return this.tree.module.Node_getScrollHeight(
      this.tree.ptr,
      this.id,
    );
  }
  get scrollLeft() {
    this.assertNotDisposed();
    return this.tree.module.Node_getScrollLeft(
      this.tree.ptr,
      this.id,
    );
  }
  get parent(): Element | null {
    this.assertNotDisposed();

    const parentId =
      this.tree.module.Tree_getNodeParent(
        this.document.tree.ptr,
        this.id,
      );

    if (parentId === -1) {
      return null;
    }
    return Element.fromNode(
      this.document,
      parentId,
    );
  }
  set scrollLeft(value: number) {
    this.tree.module.Node_setScrollLeft(
      this.tree.ptr,
      this.id,
      value,
    );
  }
  get scrollTop() {
    return this.tree.module.Node_getScrollTop(
      this.tree.ptr,
      this.id,
    );
  }
  set scrollTop(value: number) {
    this.tree.module.Node_setScrollTop(
      this.tree.ptr,
      this.id,
      value,
    );
  }
  get scrollLeftMax() {
    this.assertNotDisposed();
    return this.tree.module.Node_getScrollLeftMax(
      this.tree.ptr,
      this.id,
    );
  }
  get scrollTopMax() {
    this.assertNotDisposed();
    return this.tree.module.Node_getScrollTopMax(
      this.tree.ptr,
      this.id,
    );
  }
  
  // canScroll(direction: number, delta: number): boolean {
  //   this.assertNotDisposed();
  //   return this.tree.module.Node_canScroll(
  //     this.tree.ptr,
  //     this.id,
  //     direction,
  //     delta,
  //   );
  // }

  static fromNode(
    document: Document,
    node: number,
  ) {
    {
      const element = document.getElement(node);
      if (element) {
        return element as Element;
      }
    }
    const element = new Element(document, node);
    element.document = document;
    return element;
  }


  appendChild = (
    child: Element | TextElement,
  ) => {
    this.assertNotDisposed();
    assert(
      child.id !== this.id,
      "Cannot append child to itself",
    );
    this.tree.module.Tree_appendChild(
      this.tree.ptr,
      this.id,
      child.id,
    );
    this.document.requestPaint();
  };
  removeChild = (
    child: Element | TextElement,
  ) => {
    this.assertNotDisposed();
    assert(
      child.id !== this.id,
      "Cannot remove child from itself",
    );
    this.tree.module.Tree_removeChild(
      this.tree.ptr,
      this.id,
      child.id,
    );
    this.document.requestPaint();
  };

  removeChildren = () => {
    this.assertNotDisposed();
    const children = this.getChildren();
    this.tree.module.Tree_removeChildren(
      this.tree.ptr,
      this.id,
    );
    this.document.requestPaint();
    return children;
  };

  insertBefore = (
    child: Element | TextElement,
    before: Element | TextElement,
  ) => {
    this.assertNotDisposed();
    assert(
      child.id !== this.id,
      "Cannot insert child before itself",
    );
    assert(
      before.id !== this.id,
      "Cannot insert before itself",
    );
    this.document.requestPaint();
    this.tree.module.Tree_insertBefore(
      this.tree.ptr,
      this.id,
      child.id,
      before.id,
    );
  };
  setStyle = (style: string) => {
    this.assertNotDisposed();
    this.tree.module.Tree_setStyle(
      this.tree.ptr,
      this.id,
      style,
    );
    this.document.requestPaint();
  };
  setStyleProperty = (
    key: string,
    value: string,
  ) => {
    this.assertNotDisposed();
    this.tree.module.Tree_setStyleProperty(
      this.tree.ptr,
      this.id,
      key,
      value,
    );
    this.document.requestPaint();
  };

  getChildren = () => {
    this.assertNotDisposed();
    const count =
      this.tree.module.Tree_getChildrenCount(
        this.tree.ptr,
        this.id,
      );
    if (count === 0) {
      return [];
    }
    const children =
      this.tree.module.Tree_getChildren(
        this.tree.ptr,
        this.id,
      );

    const childrenArray = new Uint32Array(
      this.tree.module.memory.buffer,
      children,
      count,
    );
    return [...childrenArray].map((ptr) => {
      const kind =
        this.tree.module.Tree_getNodeKind(
          this.tree.ptr,
          ptr,
        );
      if (kind === 1) {
        return Element.fromNode(
          this.document,
          ptr,
        );
      }
      if (kind === 2) {
        return TextElement.fromNode(
          this.document,
          ptr,
        );
      }
      throw new Error("Unknown node kind");
    });
  };
  setText = (text: string) => {
    const children = this.removeChildren();

    for (const child of children) {
      child.dispose();
    }
    const textNode =
      this.document.createTextNode(text);
    this.appendChild(textNode);
    this.document.requestPaint();
  };


  private setScrollPosition(x: number, y: number) {
    this.scrollLeft = x;
    this.scrollTop = y;
    this.document.requestPaint();
  }

  scrollTo(options: ScrollOptions): void;
  scrollTo(x: number, y: number): void;
  scrollTo(xOrOptions: number | ScrollOptions, y?: number ): void {
    if (typeof xOrOptions === "number") {
      this.setScrollPosition(xOrOptions, y ?? 0);
    } else {
      this.setScrollPosition(xOrOptions.left ?? 0, xOrOptions.top ?? 0);
    }
  };
  scrollBy(options: ScrollOptions): void;
  scrollBy(x: number, y: number): void;
  scrollBy(xOrOptions: number | ScrollOptions, deltaY?: number ): void {
    let x = this.scrollLeft;
    let y = this.scrollTop;
    if (typeof xOrOptions === "number") {
      x += xOrOptions;
      y += deltaY ?? 0;
    } else {
      x += xOrOptions.left ?? 0;
      y += deltaY ?? 0;
    }
    this.setScrollPosition(x, y);
  };
  emitEvent = (event: DOMEvent) => {
    const set = this.listeners.get(event.type);
    if (set) {
      for (const listener of set) {
        listener(event);
      }
    }
  };
  addEventListener = <
    const K extends DOMEvent["type"],
  >(
    event: K,
    listener: (
      event: DOMEventByType<K>,
    ) => void,
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
      event: DOMEventByType<K>,
    ) => void,
  ) => {
    const set = this.listeners.get(event);
    set?.delete(
      listener as (event: DOMEvent) => void,
    );
  };

  [Symbol.for("nodejs.util.inspect.custom")]() {
    let tag = "view";
    if (this.isDisposed()) {
      return `<${tag} (DISPOSED ${this.id})/>`;
    }
    if (this.hasAttribute("id")) {
      tag += ` id="${this.getAttribute("id")}"`;
    }

    const children = this.getChildren();
    if (children.length === 0) {
      return `<${tag} (${this.id})/>`;
    }
    let childrenString = "";

    for (const child of children) {
      // @ts-expect-error
      const childString = child[Symbol.for("nodejs.util.inspect.custom")]();
      for (const line of childString.split("\n")) {
        childrenString += `  ${line}\n`;
      }
    }
    return `<${tag} (${this.id})>\n${childrenString}</${tag}>`;
  }
  disposeRecursively = () => {
    if (this.isDisposed()) {
      return;
    }
    for (const child of this.getChildren()) {
      child.disposeRecursively();
    }
    this.dispose();
  };
  assertNotDisposed = () => {
    if (!this.document.getElement(this.id)) {
      throw new Error(
        `Node ${this.id} has already been disposed`,
      );
    }
  };
  isDisposed = () => {
    return !this.document.getElement(this.id);
  };
  dispose = () => {
    this.assertNotDisposed();

    this.document.removeElement(this);
    super.dispose();
  };
  [Symbol.dispose] = () => {
    this.dispose();
  };
}
