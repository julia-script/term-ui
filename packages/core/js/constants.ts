/**
 * Constants for Selection operations
 */

/**
 * Direction for extending selection
 */
export const SelectionExtendDirection = {
  forward: 0,
  backward: 1,
} as const;

export type SelectionExtendDirection =
  (typeof SelectionExtendDirection)[keyof typeof SelectionExtendDirection];

/**
 * Granularity levels for selection movement
 */
export const SelectionExtendGranularity = {
  character: 0,
  // word: 1, TODO
  line: 2,
  lineboundary: 3,
  documentBoundary: 4,
} as const;

export type SelectionExtendGranularity =
  (typeof SelectionExtendGranularity)[keyof typeof SelectionExtendGranularity];

/**
 * Selection direction values
 */
export const SelectionDirection = {
  forward: 1,
  backward: -1,
  none: 0,
} as const;

export type SelectionDirection =
  (typeof SelectionDirection)[keyof typeof SelectionDirection];

export const HitTestFilter = {
  BOX: 0b0001,
  INCLUDE_DISABLED_POINTER_EVENTS: 0b0010,
  TEXT_FRAGMENT: 0b0100,
  SELECTION_OVERLAY: 0b1000,
  LINE_BOX: 0b10000,
} as const;

/**
 * DOM compareDocumentPosition return values
 * These are bitmask flags that can be combined
 */
export const DocumentPosition = {
  DISCONNECTED: 0x01,
  PRECEDING: 0x02,
  FOLLOWING: 0x04,
  CONTAINS: 0x08,
  CONTAINED_BY: 0x10,
} as const;

export type DocumentPosition =
  (typeof DocumentPosition)[keyof typeof DocumentPosition];
