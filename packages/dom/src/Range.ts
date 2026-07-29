import type { Document } from "./Document";

export class Range {
  constructor(
    private document: Document,
    public id: number,
  ) {}

  setStart(nodeId: number, offset: number) {
    this.document.module.Range_setStart(
      this.document.tree.ptr,
      this.id,
      nodeId,
      offset,
    );
  }

  setEnd(nodeId: number, offset: number) {
    this.document.module.Range_setEnd(
      this.document.tree.ptr,
      this.id,
      nodeId,
      offset,
    );
  }

  collapse(toStart: boolean = true) {
    this.document.module.Range_collapse(
      this.document.tree.ptr,
      this.id,
      toStart,
    );
  }

  deleteContents() {
    this.document.module.Range_deleteContents(
      this.document.tree.ptr,
      this.id,
    );
  }

  insertNode(nodeId: number) {
    this.document.module.Range_insertNode(
      this.document.tree.ptr,
      this.id,
      nodeId,
    );
  }
}