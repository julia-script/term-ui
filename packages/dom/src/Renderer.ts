import type { Module } from "@term-ui/core";
import type { WriteStream } from "@term-ui/shared/types";
import type { Tree } from "./Tree";

export class Renderer {
  ptr: number;

  constructor(
    public module: Module,
    public stdout: WriteStream,
  ) {
    this.ptr = module.Renderer_init();
  }
  static init(
    module: Module,
    stdout: WriteStream,
  ) {
    return new Renderer(module, stdout);
  }

  hitTest(
    tree: Tree,
    x: number,
    y: number,
    filter: number,
  ) {
    return this.module.Tree_hitTest(
      tree.ptr,
      x,
      y,
      filter,
    );
  }
  // getNodeAt(x: number, y: number, tree: Tree) {
  //   return this.module.Tree_hitTest(
  //     tree.ptr,
  //     x,
  //     y,
  //   );
  // }
  // renderToStdout(
  //   tree: Tree,
  //   clearScreen = false,
  // ) {
  //   this.module.Renderer_renderToStdout(
  //     this.ptr,
  //     tree.ptr,
  //     clearScreen,
  //   );
  // }
  paintSimple(tree: Tree) {
    this.module.Tree_paintSimple(
      tree.ptr,
      this.ptr,
    );
  }
  paint(tree: Tree) {
    this.module.Tree_paintApp(tree.ptr, this.ptr);
  }

  dispose() {
    this.module.Renderer_deinit(this.ptr);
  }
  [Symbol.dispose]() {
    this.dispose();
  }
}
