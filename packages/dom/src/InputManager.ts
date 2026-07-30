import type { Module } from "@term-ui/core";
import type { ReadStream } from "@term-ui/shared/types";
import { ByteArrayList } from "./ByteArrayList";
import type { Tree } from "./Tree";

const SHIFT = 1 << 0;
const ALT = 1 << 1;
const CTRL = 1 << 2;
const SUPER = 1 << 3;
const HYPER = 1 << 4;
const META = 1 << 5;
const CAPS_LOCK = 1 << 6;
const NUM_LOCK = 1 << 7;
const decoder = new TextDecoder();
export type KeyEvent = {
  kind: "key";
  key?: KeyName;
  codepoint: number;
  baseCodepoint: number;
  action: "press" | "repeat" | "release";
  rawAction: number;
  rawModifiers: number;
  source: Uint32Array;
  text: string;

  shift: boolean;
  ctrl: boolean;
  alt: boolean;
  super: boolean;
  hyper: boolean;
  meta: boolean;
  capsLock: boolean;
  numLock: boolean;
};

// Mouse event types matching Zig implementation
export type NormalMouseAction =
  | "left_press"
  | "middle_press"
  | "right_press"
  | "release"
  | "wheel_forward"
  | "wheel_back"
  | "wheel_tilt_left"
  | "wheel_tilt_right";

export type ExtendedMouseButton =
  | "left"
  | "middle"
  | "right"
  | "wheel"
  | "button8"
  | "button9"
  | "button10"
  | "button11"
  | "none";

export type ExtendedMouseAction =
  | "press"
  | "release"
  | "motion"
  | "wheel_up"
  | "wheel_down"
  | "wheel_left"
  | "wheel_right";

export type NormalMouseEvent = {
  kind: "mouse-legacy";
  action: NormalMouseAction;
  x: number;
  y: number;
  rawModifiers: number;
  shift: boolean;
  ctrl: boolean;
  alt: boolean;
  super: boolean;
  hyper: boolean;
  meta: boolean;
  capsLock: boolean;
  numLock: boolean;
};

export type ExtendedMouseEvent = {
  kind: "mouse";
  button: ExtendedMouseButton;
  action: ExtendedMouseAction;
  x: number;
  y: number;
  rawModifiers: number;
  shift: boolean;
  ctrl: boolean;
  alt: boolean;
  super: boolean;
  hyper: boolean;
  meta: boolean;
  capsLock: boolean;
  numLock: boolean;
};

export type MouseEvent =
  | NormalMouseEvent
  | ExtendedMouseEvent;

export type CursorReportEvent = {
  kind: "cursor_report";
  row: number;
  col: number;
};

const keyNameMap = {
  // Alphabets
  [97]: "a",
  [98]: "b",
  [99]: "c",
  [100]: "d",
  [101]: "e",
  [102]: "f",
  [103]: "g",
  [104]: "h",
  [105]: "i",
  [106]: "j",
  [107]: "k",
  [108]: "l",
  [109]: "m",
  [110]: "n",
  [111]: "o",
  [112]: "p",
  [113]: "q",
  [114]: "r",
  [115]: "s",
  [116]: "t",
  [117]: "u",
  [118]: "v",
  [119]: "w",
  [120]: "x",
  [121]: "y",
  [122]: "z",
  // Numbers
  [48]: "0",
  [49]: "1",
  [50]: "2",
  [51]: "3",
  [52]: "4",
  [53]: "5",
  [54]: "6",
  [55]: "7",
  [56]: "8",
  [57]: "9",
  // Special characters
  [59]: "semicolon",
  [44]: "comma",
  [46]: "period",
  [47]: "slash",
  [45]: "minus",
  [43]: "plus",
  [61]: "equal",
  [91]: "left_bracket",
  [93]: "right_bracket",
  [92]: "backslash",
  [96]: "grave_accent",
  [39]: "apostrophe",
  // Function keys
  [57344]: "escape",
  [57345]: "enter",
  [57346]: "tab",
  [57347]: "backspace",
  [57348]: "insert",
  [57349]: "delete",
  [57350]: "left",
  [57351]: "right",
  [57352]: "up",
  [57353]: "down",
  [57354]: "page_up",
  [57355]: "page_down",
  [57356]: "home",
  [57357]: "end",
  [57358]: "caps_lock",
  [57359]: "scroll_lock",
  [57360]: "num_lock",
  [57361]: "print_screen",
  [57362]: "pause",
  [57364]: "f1",
  [57365]: "f2",
  [57366]: "f3",
  [57367]: "f4",
  [57368]: "f5",
  [57369]: "f6",
  [57370]: "f7",
  [57371]: "f8",
  [57372]: "f9",
  [57373]: "f10",
  [57374]: "f11",
  [57375]: "f12",
  [57376]: "f13",
  [57377]: "f14",
  [57378]: "f15",
  [57379]: "f16",
  [57380]: "f17",
  [57381]: "f18",
  [57382]: "f19",
  [57383]: "f20",
  [57384]: "f21",
  [57385]: "f22",
  [57386]: "f23",
  [57387]: "f24",
  [57388]: "f25",
  // Keypad
  [57399]: "kp_0",
  [57400]: "kp_1",
  [57401]: "kp_2",
  [57402]: "kp_3",
  [57403]: "kp_4",
  [57404]: "kp_5",
  [57405]: "kp_6",
  [57406]: "kp_7",
  [57407]: "kp_8",
  [57408]: "kp_9",
  [57409]: "kp_decimal",
  [57410]: "kp_divide",
  [57411]: "kp_multiply",
  [57412]: "kp_subtract",
  [57413]: "kp_add",
  [57414]: "kp_enter",
  [57415]: "kp_equal",
  [57416]: "kp_separator",
  [57417]: "kp_left",
  [57418]: "kp_right",
  [57419]: "kp_up",
  [57420]: "kp_down",
  [57421]: "kp_page_up",
  [57422]: "kp_page_down",
  [57423]: "kp_home",
  [57424]: "kp_end",
  [57425]: "kp_insert",
  [57426]: "kp_delete",
  [57427]: "kp_begin",
  // Modifiers
  [57441]: "left_shift",
  [57442]: "left_control",
  [57443]: "left_alt",
  [57444]: "left_super",
  [57447]: "right_shift",
  [57448]: "right_control",
  [57449]: "right_alt",
  [57450]: "right_super",
  // Space
  [57363]: "space",
} as const;

// Mapping for mouse action codes from Zig
const normalMouseActionMap: Record<
  number,
  NormalMouseAction
> = {
  0: "left_press",
  1: "middle_press",
  2: "right_press",
  3: "release",
  4: "wheel_forward",
  5: "wheel_back",
  6: "wheel_tilt_left",
  7: "wheel_tilt_right",
};

// Mapping for extended mouse button codes from Zig
const extendedMouseButtonMap: Record<
  number,
  ExtendedMouseButton
> = {
  0: "left",
  1: "middle",
  2: "right",
  3: "wheel",
  4: "button8",
  5: "button9",
  6: "button10",
  7: "button11",
  8: "none",
};

// Mapping for extended mouse action codes from Zig
const extendedMouseActionMap: Record<
  number,
  ExtendedMouseAction
> = {
  0: "press",
  1: "release",
  2: "motion",
  3: "wheel_up",
  4: "wheel_down",
  5: "wheel_left",
  6: "wheel_right",
};

export type KeyName =
  typeof keyNameMap extends Record<
    string,
    infer K
  >
    ? K
    : never;

export type PasteEvent = {
  kind: "paste";
  text: string;
};
export type InputEvent =
  | KeyEvent
  | PasteEvent
  | ExtendedMouseEvent
  | NormalMouseEvent
  | CursorReportEvent;
const printableRegex = /^[^\p{C}]+$/u;

export const isPrintable = (
  input: string,
): boolean => {
  return printableRegex.test(input);
};

const getTextFromCodepoint = (
  codepoint: number,
) => {
  switch (codepoint) {
    case 0x0:
      return "";
    case 57346:
      return "\t";
    case 57345:
      return "\n";
  }
  const text = String.fromCodePoint(codepoint);
  if (isPrintable(text)) {
    return text;
  }

  return "";
};

export class InputManager {
  buffer: ByteArrayList;
  consumed = 0;
  scheduled: NodeJS.Timeout | null = null;
  pasteBuffers: Uint8Array = new Uint8Array(0);
  listeners = new Set<
    (event: InputEvent) => void
  >();
  isDisposed = false;

  private _unsubscribe: () => void;
  constructor(
    public module: Module,
    public stdin: ReadStream,
    public tree: Tree,
  ) {
    // this.ptr = module.InputManager_init();
    module.Tree_enableInputManager(tree.ptr);

    this.buffer = new ByteArrayList(module);

    this._unsubscribe = module.subscribe(
      (data) => {
        this.emitEvent(data);
      },
    );
    this.stdin.on("data", this.onData);
  }
  static init = (
    module: Module,
    stdin: ReadStream,
    tree: Tree,
  ) => {
    const inputManager = new InputManager(
      module,
      stdin,
      tree,
    );
    module.Tree_enableInputManager(tree.ptr);
    return inputManager;
  };
  private onData = (data: Uint8Array) => {
    if (this.isDisposed) {
      return;
    }
    this.buffer.appendSlice(data);
    this.consumeEvents();
  };

  dispose() {
    if (this.isDisposed) {
      return;
    }
    this.isDisposed = true;
    // this.module.InputManager_deinit(this.ptr);
    this.stdin.off("data", this.onData);
    if (this.scheduled) {
      clearTimeout(this.scheduled);
      this.scheduled = null;
    }
    this._unsubscribe();
    this.buffer.dispose();
  }

  [Symbol.dispose]() {
    this.dispose();
  }
  private emitEvent(data: Uint32Array) {
    const kind = data[0];
    switch (kind) {
      case 1: {
        const id = data[1] as number;
        const codepoint = data[2] as number;
        const baseCodepoint = data[3] as number;
        const rawAction = data[4] as number;
        const modifiers = data[5] as number;
        const action: KeyEvent["action"] =
          rawAction === 0
            ? "press"
            : rawAction === 1
              ? "repeat"
              : "release";

        const keyEvent: KeyEvent = {
          kind: "key",
          key: keyNameMap[
            baseCodepoint as keyof typeof keyNameMap
          ],
          codepoint,
          action,
          baseCodepoint,
          rawAction,
          rawModifiers: modifiers,
          source: data.slice(0, 6),
          // press and repeat both produce text (key autorepeat types);
          // release never does
          text:
            rawAction === 2
              ? ""
              : getTextFromCodepoint(codepoint),
          shift: (modifiers & SHIFT) !== 0,
          ctrl: (modifiers & CTRL) !== 0,
          alt: (modifiers & ALT) !== 0,
          super: (modifiers & SUPER) !== 0,
          hyper: (modifiers & HYPER) !== 0,
          meta: (modifiers & META) !== 0,
          capsLock: (modifiers & CAPS_LOCK) !== 0,
          numLock: (modifiers & NUM_LOCK) !== 0,
        };
        for (const listener of this.listeners) {
          listener(keyEvent);
        }

        break;
      }
      case 2: {
        this.emitOrBufferPasteEvent(data);
        break;
      }
      case 4: {
        // Normal mouse events (legacy)
        const id = data[1] as number;
        const x = data[2] as number;
        const y = data[3] as number;
        const actionCode = data[4] as number;
        const modifiers =
          data.length > 5
            ? (data[5] as number)
            : 0;

        const action =
          normalMouseActionMap[actionCode];
        if (!action) {
          console.warn(
            `Unknown normal mouse action code: ${actionCode}`,
          );
          break;
        }

        const mouseEvent: NormalMouseEvent = {
          kind: "mouse-legacy",
          action,
          x,
          y,
          rawModifiers: modifiers,
          shift: (modifiers & SHIFT) !== 0,
          ctrl: (modifiers & CTRL) !== 0,
          alt: (modifiers & ALT) !== 0,
          super: (modifiers & SUPER) !== 0,
          hyper: (modifiers & HYPER) !== 0,
          meta: (modifiers & META) !== 0,
          capsLock: (modifiers & CAPS_LOCK) !== 0,
          numLock: (modifiers & NUM_LOCK) !== 0,
        };

        for (const listener of this.listeners) {
          listener(mouseEvent);
        }
        break;
      }
      case 5: {
        // Extended mouse events
        const id = data[1] as number;
        const buttonCode = data[2] as number;
        const actionCode = data[3] as number;
        const x = data[4] as number;
        const y = data[5] as number;
        const modifiers =
          data.length > 6
            ? (data[6] as number)
            : 0;

        const button =
          extendedMouseButtonMap[buttonCode];
        const action =
          extendedMouseActionMap[actionCode];

        if (!button || !action) {
          console.warn(
            `Unknown extended mouse parameters: button=${buttonCode}, action=${actionCode}`,
          );
          break;
        }

        const mouseEvent: ExtendedMouseEvent = {
          kind: "mouse",
          button,
          action,
          x,
          y,
          rawModifiers: modifiers,
          shift: (modifiers & SHIFT) !== 0,
          ctrl: (modifiers & CTRL) !== 0,
          alt: (modifiers & ALT) !== 0,
          super: (modifiers & SUPER) !== 0,
          hyper: (modifiers & HYPER) !== 0,
          meta: (modifiers & META) !== 0,
          capsLock: (modifiers & CAPS_LOCK) !== 0,
          numLock: (modifiers & NUM_LOCK) !== 0,
        };

        for (const listener of this.listeners) {
          listener(mouseEvent);
        }
        break;
      }
      case 3: {
        // Cursor report events
        const id = data[1] as number;
        const row = data[2] as number;
        const col = data[3] as number;

        const cursorEvent: CursorReportEvent = {
          kind: "cursor_report",
          row,
          col,
        };

        for (const listener of this.listeners) {
          listener(cursorEvent);
        }
        break;
      }
    }
  }

  private emitOrBufferPasteEvent(
    data: Uint32Array,
  ) {
    const kind = data[2] as number;
    const bodyPtr = data[3] as number;
    const bodyLength = data[4] as number;

    const buffer = new Uint8Array(
      this.module.memory.buffer,
      bodyPtr,
      bodyLength,
    );
    // kind == all
    switch (kind) {
      case 3: {
        const pasteEvent: PasteEvent = {
          kind: "paste",
          text: decoder.decode(buffer),
        };
        for (const listener of this.listeners) {
          listener(pasteEvent);
        }
        break;
      }
      // kind == end
      case 1: {
        const completeBuffer = concatUint8Arrays(
          concatUint8Arrays(
            this.pasteBuffers,
            buffer,
          ),
          buffer,
        );
        this.pasteBuffers = new Uint8Array(0);
        const pasteEvent: PasteEvent = {
          kind: "paste",
          text: decoder.decode(completeBuffer),
        };
        for (const listener of this.listeners) {
          listener(pasteEvent);
        }
        break;
      }
      // kind == start
      case 0: {
        this.pasteBuffers = buffer.slice();
        break;
      }
      // kind == chunk
      case 2: {
        const newBuffer = concatUint8Arrays(
          this.pasteBuffers,
          buffer.slice(),
        );
        this.pasteBuffers = newBuffer;
        break;
      }
    }
  }
  subscribe(cb: (event: InputEvent) => void) {
    this.listeners.add(cb);
    return () => {
      this.listeners.delete(cb);
    };
  }
  clearConsumed() {
    const consumed = this.consumed;
    const len = this.buffer.length;
    const buffer = new Uint8Array(
      this.module.memory.buffer,
      this.buffer.slicePtr,
      len,
    );
    buffer.copyWithin(0, consumed, len);
    this.buffer.length = len - consumed;
    this.consumed = 0;
  }

  consumeEvents = (force = false) => {
    if (this.scheduled) {
      clearTimeout(this.scheduled);
      this.scheduled = null;
    }

    const consumed =
      this.module.Tree_consumeEvents(
        this.tree.ptr,
        this.buffer.ptr,
        force,
      );

    this.consumed += consumed;
    if (this.consumed < this.buffer.length) {
      this.scheduled = setTimeout(() => {
        this.consumeEvents(true);
      }, 50);
    }
    this.clearConsumed();

    return consumed;
  };
}

const concatUint8Arrays = (
  a: Uint8Array,
  b: Uint8Array,
) => {
  if (b.length === 0) {
    return a;
  }
  if (a.length === 0) {
    return b;
  }
  const result = new Uint8Array(
    a.length + b.length,
  );
  result.set(a);
  result.set(b, a.length);
  return result;
};
