import type { Document } from "./Document";
import type { Element } from "./Element";
import { Node } from "./Node";

export class TextElement extends Node {
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
  get parent(): Element | TextElement | null {
    const parentId =
      this.document.tree.module.Tree_getNodeParent(
        this.document.tree.ptr,
        this.id,
      );

    if (parentId === -1) {
      return null;
    }
    return this.document.getOrAddElement(
      parentId,
    );
  }
  static fromNode(
    document: Document,
    node: number,
  ) {
    {
      const element = document.getElement(node);
      if (element) {
        return element as TextElement;
      }
    }
    const element = new TextElement(
      document,
      node,
    );
    return element;
  }
  setText(text: string) {
    this.tree.module.Node_setText(
      this.tree.ptr,
      this.id,
      text,
    );
  }
  getText() {
    // wrapper returns a materialized string (reply-arena copied)
    return this.tree.module.Node_getText(
      this.tree.ptr,
      this.id,
    );
  }

  // CharacterData methods
  appendData(data: string) {
    this.tree.module.Node_appendData(
      this.tree.ptr,
      this.id,
      data,
    );
  }

  insertData(offset: number, data: string) {
    this.tree.module.Node_insertData(
      this.tree.ptr,
      this.id,
      offset,
      data,
    );
  }

  replaceData(offset: number, count: number, data: string) {
    this.tree.module.Node_replaceData(
      this.tree.ptr,
      this.id,
      offset,
      count,
      data,
    );
  }

  deleteData(offset: number, count: number) {
    this.tree.module.Node_deleteData(
      this.tree.ptr,
      this.id,
      offset,
      count,
    );
  }

  [Symbol.for("nodejs.util.inspect.custom")]() {
    return `<text (${this.id})>${this.getText()}</text>`;
  }
  dispose() {
    super.dispose();
    this.document.removeElement(this);
  }
  disposeRecursively() {
    this.dispose();
  }
  [Symbol.dispose] = () => {
    this.dispose();
  };
}
