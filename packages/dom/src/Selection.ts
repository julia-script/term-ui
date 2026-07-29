import {
  SelectionExtendDirection,
  SelectionExtendGranularity,
  DocumentPosition,
} from "@term-ui/core/constants";
import { raise } from "@term-ui/shared/raise";
import type { Document } from "./Document";
import { Range } from "./Range";

export class Selection {
  private ghostPosition: number | null = null;
  constructor(
    private document: Document,
    public id: number,
  ) {}

  get direction() {
    return this.document.module.Selection_getDirection(
      this.document.tree.ptr,
      this.id,
    );
  }
  getAnchor() {
    return this.document.module.Selection_getAnchor(
      this.document.tree.ptr,
      this.id,
    ) as { node: number; offset: number };
  }
  getFocus() {
    return this.document.module.Selection_getFocus(
      this.document.tree.ptr,
      this.id,
    ) as { node: number; offset: number };
  }
  setAnchor(node: number, offset: number) {
    this.ghostPosition = null;
    return this.document.module.Selection_setAnchor(
      this.document.tree.ptr,
      this.id,
      node,
      offset,
    );
  }
  setFocus(node: number, offset: number) {
    this.ghostPosition = null;
    return this.document.module.Selection_setFocus(
      this.document.tree.ptr,
      this.id,
      node,
      offset,
    );
  }


  modify(
    direction: keyof typeof SelectionExtendDirection,
    granularity: keyof typeof SelectionExtendGranularity,
    ghostPosition?: number,
  ) {
    if (granularity === "line") {
      if (this.ghostPosition === null) {
        const focus = this.getFocus();
        if (focus) {
          const boundaryPointPosition =
            this.document.module.Tree_getBoundaryPointPosition(
              this.document.tree.ptr,
              focus.node,
              focus.offset,
            ).x;
          this.ghostPosition =
            boundaryPointPosition;
        }
      }
    } else {
      this.ghostPosition = null;
    }
    return this.document.module.Selection_modify(
      this.document.tree.ptr,
      this.id,
      SelectionExtendDirection[direction] ??
        raise("Invalid direction"),
      SelectionExtendGranularity[granularity] ??
        raise("Invalid granularity"),
      this.ghostPosition ?? -1, // Using -1 as null value
    );
  }

  deleteFromDocument() {
    return this.document.module.Selection_deleteFromDocument(
      this.document.tree.ptr,
      this.id,
    );
  }

  collapseToStart() {
    return this.document.module.Selection_collapseToStart(
      this.document.tree.ptr,
      this.id,
    );
  }

  collapseToEnd() {
    return this.document.module.Selection_collapseToEnd(
      this.document.tree.ptr,
      this.id,
    );
  }

  isCollapsed(): boolean {
    return !!this.document.module.Selection_isCollapsed(
      this.document.tree.ptr,
      this.id,
    );
  }

  getRangeAt(index: number): Range {
    if (index !== 0) {
      throw new Error(
        "IndexSizeError: Index out of bounds",
      );
    }
    // In this implementation, the selection ID is also the range ID
    return new Range(this.document, this.id);
  }
  isEditable(): boolean {
    const anchor = this.getAnchor();
    const anchorNode = this.document.getOrAddElement(anchor.node);
    return anchorNode.isEditable();
  }

  get rangeCount(): number {
    // This implementation supports only one range per selection
    return 1;
  }
}
