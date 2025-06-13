import {
  SelectionExtendDirection,
  SelectionExtendGranularity,
} from "@term-ui/core/constants";
import { raise } from "@term-ui/shared/raise";
import type { Document } from "./Document";

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
    );
  }
  getFocus() {
    return this.document.module.Selection_getFocus(
      this.document.tree.ptr,
      this.id,
    );
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

  extendBy(
    granularity: keyof typeof SelectionExtendGranularity,
    direction: keyof typeof SelectionExtendDirection,
    rootNodeId?: number,
  ) {
    if (granularity === "line") {
      const focus = this.getFocus();
      if (
        this.ghostPosition === null &&
        focus !== null
      ) {
        this.ghostPosition =
          this.document.module.Selection_getHorizontalOffset(
            this.document.tree.ptr,
            focus.node,
            focus.offset,
          );
      }
    } else {
      this.ghostPosition = null;
    }
    return this.document.module.Selection_extendBy(
      this.document.tree.ptr,
      this.id,
      SelectionExtendGranularity[granularity] ??
        raise("Invalid granularity"),
      SelectionExtendDirection[direction] ??
        raise("Invalid direction"),
      this.ghostPosition ?? undefined,
      // Default to the tree root when no specific node is provided so
      // selection extension can cross node boundaries.
      rootNodeId ?? 0,
    );
  }
}
