import type { Element } from "../Element";
/**
 * Event type definitions following DOM standards
 */

export type EventType =
  | "mousedown"
  | "mouseup"
  | "mousemove"
  | "click"
  | "dblclick"
  | "keydown"
  | "keyup"
  | "keypress"
  | "focus"
  | "blur"
  | "input"
  | "change";

export interface BaseEvent {
  type: EventType;
  timestamp: number;
  target: Element; // Will be Element when we have proper types
  currentTarget?: Element;
  bubbles: boolean;
  cancelable: boolean;
  defaultPrevented: boolean;
  propagationStopped: boolean;
  immediatePropagationStopped: boolean;

  preventDefault(): void;
  stopPropagation(): void;
  stopImmediatePropagation(): void;
}

export interface MouseEvent extends BaseEvent {
  type:
    | "mousedown"
    | "mouseup"
    | "mousemove"
    | "click"
    | "dblclick";
  x: number;
  y: number;
  button: number; // 0: left, 1: middle, 2: right
  buttons: number; // Bitmask of pressed buttons
  clientX: number;
  clientY: number;
  screenX: number;
  screenY: number;
  movementX: number;
  movementY: number;
  ctrlKey: boolean;
  shiftKey: boolean;
  altKey: boolean;
  metaKey: boolean;
  willRelease?: boolean; // For press events, indicates if release is expected
}

export interface KeyboardEvent extends BaseEvent {
  type: "keydown" | "keyup" | "keypress";
  key: string;
  code: string;
  charCode?: number;
  keyCode?: number;
  ctrlKey: boolean;
  shiftKey: boolean;
  altKey: boolean;
  metaKey: boolean;
  repeat: boolean;
  willRelease?: boolean; // For keydown events, indicates if keyup is expected
}

export interface FocusEvent extends BaseEvent {
  type: "focus" | "blur";
  relatedTarget?: Element; // Element that lost/gained focus
}

export interface InputEvent extends BaseEvent {
  type: "input" | "change";
  data?: string;
  inputType?: string;
}

export type DOMEvent =
  | MouseEvent
  | KeyboardEvent
  | FocusEvent
  | InputEvent;

// export type EventListener = (
//   event: DOMEvent,
// ) => void;

// export interface EventTarget {
//   addEventListener(
//     type: EventType,
//     listener: EventListener,
//   ): void;
//   removeEventListener(
//     type: EventType,
//     listener: EventListener,
//   ): void;
//   dispatchEvent(event: DOMEvent): boolean;
// }

// Mouse button constants
export const MouseButton = {
  LEFT: 0,
  MIDDLE: 1,
  RIGHT: 2,
} as const;

// Mouse buttons bitmask
export const MouseButtons = {
  NONE: 0,
  LEFT: 1,
  RIGHT: 2,
  MIDDLE: 4,
} as const;

// Modifier key states
export interface ModifierState {
  ctrlKey: boolean;
  shiftKey: boolean;
  altKey: boolean;
  metaKey: boolean;
}
