import type {
  Element,
  MouseClickEvent,
  MouseDownEvent,
  MouseEnterEvent,
  MouseLeaveEvent,
  MouseMoveEvent,
  MouseUpEvent,
  ScrollEvent,
  TextElement,
} from "@term-ui/dom";
import type {
  Key,
  PropsWithChildren,
  Ref,
} from "react";

export type ElementEvents = {
  onClick?: (event: MouseClickEvent) => void;
  onMouseEnter?: (event: MouseEnterEvent) => void;
  onMouseLeave?: (event: MouseLeaveEvent) => void;
  onMouseMove?: (event: MouseMoveEvent) => void;
  onMouseDown?: (event: MouseDownEvent) => void;
  onMouseUp?: (event: MouseUpEvent) => void;
  onScroll?: (event: ScrollEvent) => void;
};

/**
 * Props for the `<view>` host element.
 *
 * @remarks
 * These types back the JSX namespace exported from `@term-ui/react/jsx-runtime`,
 * which *replaces* React's intrinsic element table rather than merging with it.
 * Anything omitted here is a hard type error at the call site, so this must
 * carry every prop a host element accepts — `key`, `ref` and `children`
 * included.
 */
export type TermViewProps = PropsWithChildren<
  {
    key?: Key;
    /** Receives the underlying DOM-layer element once mounted. */
    ref?: Ref<Element>;
    style?: React.CSSProperties;
    contentEditable?: boolean;
  } & ElementEvents
>;

/** Props for the `<text>` host element. See {@link TermViewProps}. */
export type TermTextProps = PropsWithChildren<{
  key?: Key;
  ref?: Ref<Element | TextElement>;
  style?: React.CSSProperties;
  contentEditable?: boolean;
}>;
