import type {
  ReadStream,
  WriteStream,
} from "@term-ui/shared/types";
import type { Document } from "./Document";
import type { Element } from "./Element";
import type {
  InputEvent,
  KeyName,
} from "./InputManager";

export type Size<T = number> = {
  width: T;
  height: T;
};
// export type DomEvent =
//   | MouseEnterEvent
//   | MouseLeaveEvent
//   | MouseMoveEvent
//   | MouseDownEvent
//   | MouseUpEvent
//   | MouseClickEvent
//   | ScrollEvent
//   | KeydownEvent
//   | KeyupEvent
//   | KeypressEvent;
export type MouseEnterEvent = {
  type: "mouseenter";
  target: Element;
  document: Document;
};
export type MouseLeaveEvent = {
  type: "mouseleave";
  target: Element;
  document: Document;
};
export type MouseMoveEvent = {
  kind: "mousemove";
  target: Element;
  document: Document;
  x: number;
  y: number;
};
export type MouseDownEvent = {
  type: "mousedown";
  target: Element;
  document: Document;
  x: number;
  y: number;
};
export type MouseUpEvent = {
  type: "mouseup";
  target: Element;
  document: Document;
  x: number;
  y: number;
};
export type MouseClickEvent = {
  type: "click";
  target: Element;
  document: Document;
  x: number;
  y: number;
};
// export type ScrollEvent = {
//   kind: "scroll";
//   target: Element;
//   document: Document;
//   deltaX: number;
//   deltaY: number;
//   preventDefault: () => void;
// };

export type BaseKeyEvent = {
  target: Element;
  document: Document;
  key?: KeyName;
  codepoint: number;
  text: string;
  shift: boolean;
  ctrl: boolean;
  alt: boolean;
  super: boolean;
  meta: boolean;
  repeat?: boolean;
  preventDefault: () => void;
};

export type KeydownEvent = BaseKeyEvent & {
  type: "keydown";
};

export type KeyupEvent = BaseKeyEvent & {
  type: "keyup";
};

export type KeypressEvent = BaseKeyEvent & {
  type: "keypress";
};

export type RenderingSize = Size<
  | number
  | "min-content"
  | "max-content"
  | `${number}%`
>;
export type DocumentOptions = {
  writeStream: WriteStream;
  readStream: ReadStream;
  size: RenderingSize;
  reportLeaksOnExit: boolean;
  enableInputs: boolean;
  exitOnCtrlC: boolean;
  enableAlternateScreen: boolean;
  clearScreenBeforePaint: boolean;
  onPaintRequest?: () => void;
  /**
   * Wraps every input-event dispatch. Lets embedders bracket dispatch with
   * ambient state (e.g. React update priority) without the dom package
   * depending on them. Must call `dispatch` exactly once, synchronously.
   */
  wrapInputDispatch?: (
    event: InputEvent,
    dispatch: () => void,
  ) => void;
};

export type EventTarget = Element | Document;
export type KeyboardEvent = {
  type: "keydown" | "keyup" | "keypress";
  target: EventTarget;
  currentTarget: EventTarget;
  key: string;
  code: string;
  charCode?: number;
  text: string;
  keyCode?: number;
  bubbles: boolean;
  defaultPrevented: boolean;
  cancelable: boolean;
  preventDefault: () => void;
  stopPropagation: () => void;
  shiftKey: boolean;
  ctrlKey: boolean;
  altKey: boolean;
  metaKey: boolean;
  repeat: boolean;
};

// mousedown, mouseenter, mouseleave, mousemove, mouseout, mouseover, or mouseup.
export type MouseEvent = {
  type:
    | "mousedown"
    | "mouseup"
    | "mousemove"
    | "mouseenter"
    | "mouseleave"
    | "mouseout"
    | "mouseover"
    | "click";
  button: string;
  clientX: number;
  clientY: number;
  target: EventTarget;
  currentTarget: EventTarget;
  bubbles: boolean;
  defaultPrevented: boolean;
  cancelable: boolean;
  preventDefault: () => void;
  stopPropagation: () => void;
  shiftKey: boolean;
  ctrlKey: boolean;
  altKey: boolean;
  metaKey: boolean;
};

export type WheelEvent = {
  type: "wheel";
  target: EventTarget;
  currentTarget: EventTarget;
  deltaX: number;
  deltaY: number;
  bubbles: boolean;
  button: string;
  clientX: number;
  clientY: number;
  defaultPrevented: boolean;
  cancelable: boolean;
  preventDefault: () => void;
  stopPropagation: () => void;
  shiftKey: boolean;
  ctrlKey: boolean;
  altKey: boolean;
  metaKey: boolean;
} 
export type ScrollEvent = {
  type: "scroll";
  target: EventTarget;
  currentTarget: EventTarget | null;
  bubbles: boolean;
  defaultPrevented: boolean;
  cancelable: boolean;
  preventDefault: () => void;
  stopPropagation: () => void;

}

export type DOMEvent =
  | KeyboardEvent
  | MouseEvent
  | WheelEvent
  | ScrollEvent;








export type DOMEventByType<T extends DOMEvent["type"]> =  T extends DOMEvent["type"] ? DOMEvent & { type: T } : never;

export type test = DOMEventByType<"mousemove">; 
//           ^?