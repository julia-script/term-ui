import type {
  MouseClickEvent,
  MouseDownEvent,
  MouseEnterEvent,
  MouseLeaveEvent,
  MouseMoveEvent,
  MouseUpEvent,
  ScrollEvent,
} from "@term-ui/dom";
import type { PropsWithChildren } from "react";

export type ElementEvents = {
  onClick?: (event: MouseClickEvent) => void;
  onMouseEnter?: (event: MouseEnterEvent) => void;
  onMouseLeave?: (event: MouseLeaveEvent) => void;
  onMouseMove?: (event: MouseMoveEvent) => void;
  onMouseDown?: (event: MouseDownEvent) => void;
  onMouseUp?: (event: MouseUpEvent) => void;
  onScroll?: (event: ScrollEvent) => void;
};
export type TermViewProps = PropsWithChildren<
  {
    key?: string;
    style?: React.CSSProperties;
    contentEditable?: boolean;
  } & ElementEvents
>;
export type TermTextProps = PropsWithChildren<{
  key?: string;
  style?: React.CSSProperties;
  contentEditable?: boolean;
}>;
