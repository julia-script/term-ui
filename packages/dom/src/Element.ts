import { assert } from "@term-ui/shared/assert";
import { clamp } from "@term-ui/shared/clamp";
import type { Document } from "./Document";
import { Node } from "./Node";
import { TextElement } from "./TextElement";

import type { DOMEvent, DOMEventByType } from "./types";

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
  }
  get clientWidth() {
    this.assertNotDisposed();
    return this.tree.module.Tree_getNodeClientWidth(
      this.tree.ptr,
      this.id,
    );
  }
  get clientHeight() {
    this.assertNotDisposed();
    return this.tree.module.Tree_getNodeClientHeight(
      this.tree.ptr,
      this.id,
    );
  }
  get scrollWidth() {
    this.assertNotDisposed();
    return this.tree.module.Tree_getNodeScrollWidth(
      this.tree.ptr,
      this.id,
    );
  }
  get scrollHeight() {
    this.assertNotDisposed();
    return this.tree.module.Tree_getNodeScrollHeight(
      this.tree.ptr,
      this.id,
    );
  }
  get scrollLeft() {
    this.assertNotDisposed();
    return this.tree.module.Tree_getNodeScrollLeft(
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
    this.tree.module.Tree_setNodeScrollLeft(
      this.tree.ptr,
      this.id,
      clamp(
        value,
        0,
        this.scrollWidth - this.clientWidth,
      ),
    );
  }
  get scrollTop() {
    return this.tree.module.Tree_getNodeScrollTop(
      this.tree.ptr,
      this.id,
    );
  }
  set scrollTop(value: number) {
    this.tree.module.Tree_setNodeScrollTop(
      this.tree.ptr,
      this.id,
      clamp(
        value,
        0,
        this.scrollHeight - this.clientHeight,
      ),
    );
  }

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
  };

  removeChildren = () => {
    this.assertNotDisposed();
    const children = this.getChildren();
    this.tree.module.Tree_removeChildren(
      this.tree.ptr,
      this.id,
    );
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
    return `<view (${this.id})/>`;
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
