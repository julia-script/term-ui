import type { Tree } from "./Tree";

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export class Node {
  tree: Tree;
  id: number;
  constructor(tree: Tree, id: number) {
    this.tree = tree;
    this.id = id;
  }
  getKind() {
    return this.tree.module.Tree_getNodeKind(
      this.tree.ptr,
      this.id,
    );
  }
  getKindName() {
    switch (this.getKind()) {
      case 1:
        return "ELEMENT_NODE";
      case 2:
        return "TEXT_NODE";
      default:
        return "UNKNOWN";
    }
  }
  setStyle(style: string) {
    this.tree.module.Tree_setStyle(
      this.tree.ptr,
      this.id,
      style,
    );
  }
  dispose() {
    this.tree.module.Tree_destroyNode(
      this.tree.ptr,
      this.id,
    );
  }
  [Symbol.dispose]() {
    this.dispose();
  }

  // Attribute methods
  setAttribute(name: string, value: string) {
    this.tree.module.Node_setAttribute(
      this.tree.ptr,
      this.id,
      name,
      value,
    );
  }

  getAttribute(name: string): string | null {
    return this.tree.module.Node_getAttribute(
      this.tree.ptr,
      this.id,
      name,
    );
  }

  hasAttribute(name: string): boolean {
    return this.tree.module.Node_hasAttribute(
      this.tree.ptr,
      this.id,
      name,
    );
  }

  removeAttribute(name: string) {
    this.tree.module.Node_removeAttribute(
      this.tree.ptr,
      this.id,
      name,
    );
  }

  // Editing host methods
  isEditingHost(): boolean {
    return this.tree.module.Node_isEditingHost(
      this.tree.ptr,
      this.id,
    );
  }

  isEditable(): boolean {
    return this.tree.module.Node_isEditable(
      this.tree.ptr,
      this.id,
    );
  }

  getEditingHost(): number | null {
    const hostId = this.tree.module.Node_getEditingHost(
      this.tree.ptr,
      this.id,
    );
    return hostId === -1 ? null : hostId;
  }

  inSameEditingHost(otherId: number): boolean {
    return this.tree.module.Node_inSameEditingHost(
      this.tree.ptr,
      this.id,
      otherId,
    );
  }

  // DOM comparison
  compareDocumentPosition(otherId: number): number {
    return this.tree.module.Node_compareDocumentPosition(
      this.tree.ptr,
      this.id,
      otherId,
    );
  }

  // Client rect methods
  getClientRects(): Rect[] {
    return this.tree.module.Node_getClientRects(
      this.tree.ptr,
      this.id,
    );
  }

  getBoundingClientRect(): Rect {
    return this.tree.module.Node_getBoundingClientRect(
      this.tree.ptr,
      this.id,
    );
  }
}
