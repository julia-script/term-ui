import { csi } from "./utils";

export const ENABLE_ALTERNATE_SCREEN =
  csi("?1049h");
export const DISABLE_ALTERNATE_SCREEN =
  csi("?1049l");
export const CLEAR_SCROLLBACK_BUFFER = csi("3J");

// CSI Ps SP q
//           Set cursor style (DECSCUSR, VT520).
export const CURSOR_BLINKING_BLOCK = csi("0 q");
export const CURSOR_BLINKING_BLOCK_DEFAULT = csi("1 q");
export const CURSOR_STEADY_BLOCK = csi("2 q");
export const CURSOR_BLINKING_UNDERLINE = csi("3 q");
export const CURSOR_STEADY_UNDERLINE = csi("4 q");
export const CURSOR_BLINKING_BAR = csi("5 q");
export const CURSOR_STEADY_BAR = csi("6 q");
export const HIDE_CURSOR = csi("?25l");
export const SHOW_CURSOR = csi("?25h");
// #define SET_X10_MOUSE               9
// #define SET_VT200_MOUSE             1000
// #define SET_VT200_HIGHLIGHT_MOUSE   1001
// #define SET_BTN_EVENT_MOUSE         1002
// #define SET_ANY_EVENT_MOUSE         1003

// #define SET_FOCUS_EVENT_MOUSE       1004

// #define SET_EXT_MODE_MOUSE          1005
// #define SET_SGR_EXT_MODE_MOUSE      1006
// #define SET_URXVT_EXT_MODE_MOUSE    1015

// #define SET_ALTERNATE_SCROLL        1007
export const ENABLE_X10_MOUSE = csi("?9h");
export const DISABLE_X10_MOUSE = csi("?9l");

export const ENABLE_VT200_MOUSE = csi("?1000h");
export const DISABLE_VT200_MOUSE = csi("?1000l");

export const ENABLE_VT200_HIGHLIGHT_MOUSE =
  csi("?1001h");
export const DISABLE_VT200_HIGHLIGHT_MOUSE =
  csi("?1001l");

export const ENABLE_BTN_EVENT_MOUSE =
  csi("?1002h");
export const DISABLE_BTN_EVENT_MOUSE =
  csi("?1002l");

export const ENABLE_ANY_EVENT_MOUSE =
  csi("?1003h");
export const DISABLE_ANY_EVENT_MOUSE =
  csi("?1003l");

export const ENABLE_FOCUS_EVENT_MOUSE =
  csi("?1004h");
export const DISABLE_FOCUS_EVENT_MOUSE =
  csi("?1004l");

export const ENABLE_EXT_MODE_MOUSE =
  csi("?1005h");
export const DISABLE_EXT_MODE_MOUSE =
  csi("?1005l");

export const ENABLE_SGR_EXT_MODE_MOUSE =
  csi("?1006h");
export const DISABLE_SGR_EXT_MODE_MOUSE =
  csi("?1006l");

export const ENABLE_URXVT_EXT_MODE_MOUSE =
  csi("?1015h");
export const DISABLE_URXVT_EXT_MODE_MOUSE =
  csi("?1015l");

export const ENABLE_SCREEN_WRAP_MODE = csi("?7h");
export const DISABLE_SCREEN_WRAP_MODE =
  csi("?7l");
