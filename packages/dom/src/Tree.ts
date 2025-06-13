import type { Module } from "@term-ui/core";
import { Node } from "./Node";
export class Tree {
  module: Module;
  ptr: number;
  is_disposed = false;

  constructor(module: Module) {
    this.module = module;
    this.ptr = module.Tree_init();
  }
  static init(module: Module) {
    return new Tree(module);
  }

  createNode = (style: string) => {
    this.assertNotDisposed();
    const ptr = this.module.Tree_createNode(
      this.ptr,
      style,
    );
    return new Node(this, ptr);
  };
  createTextNode = (text: string) => {
    this.assertNotDisposed();
    const ptr = this.module.Tree_createTextNode(
      this.ptr,
      text,
    );
    return new Node(this, ptr);
  };

  assertNotDisposed() {
    if (this.is_disposed) {
      throw new Error("Tree already disposed");
    }
  }
  computeStyles() {
    this.assertNotDisposed();
    this.module.Tree_computeStyles(this.ptr);
  }
  buildLayoutTree() {
    this.assertNotDisposed();
    this.module.Tree_buildLayoutTree(this.ptr);
  }
  computeLayout(
    width: number | "min-content" | "max-content",
    height:
      | number
      | "min-content"
      | "max-content",
  ) {
    this.assertNotDisposed();
    this.module.Tree_computeLayout(
      this.ptr,
      width.toString(),
      height.toString(),
    );
  }
  dump() {
    this.assertNotDisposed();
    this.module.Tree_dump(this.ptr);
  }
  dispose() {
    this.assertNotDisposed();
    this.is_disposed = true;
    this.module.Tree_deinit(this.ptr);
  }

  [Symbol.dispose]() {
    this.dispose();
  }
}
