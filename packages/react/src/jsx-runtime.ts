/**
 * JSX runtime for term-ui's host elements.
 *
 * @remarks
 * Set `"jsxImportSource": "@term-ui/react"` in tsconfig and TypeScript resolves
 * `JSX.IntrinsicElements` from *this module* instead of the global namespace
 * `@types/react` augments. That is what lets `<view>` and `<text>` be our
 * elements: React's own types declare both as SVG intrinsics
 * (`SVGViewElement` / `SVGTextElement`), and a global augmentation can only add
 * keys, never redeclare them.
 *
 * The runtime itself is React's, re-exported unchanged — this module is a
 * type-level redirect, not a second renderer.
 */
export {
  Fragment,
  jsx,
  jsxs,
} from "react/jsx-runtime";

import type { JSX as ReactJSX } from "react/jsx-runtime";
import type {
  TermTextProps,
  TermViewProps,
} from "./types.js";

export namespace JSX {
  /** The host elements term-ui renders — this is the whole table. */
  export interface IntrinsicElements {
    view: TermViewProps;
    text: TermTextProps;
  }

  // Everything else keeps React's semantics. The namespace *replaces* React's
  // rather than merging with it, so each member has to be carried over
  // explicitly — omitting IntrinsicAttributes, for instance, would strip `key`
  // from every component call site.
  export type ElementType = ReactJSX.ElementType;
  export type Element = ReactJSX.Element;
  export type ElementClass = ReactJSX.ElementClass;
  export type ElementAttributesProperty =
    ReactJSX.ElementAttributesProperty;
  export type ElementChildrenAttribute =
    ReactJSX.ElementChildrenAttribute;
  export type LibraryManagedAttributes<C, P> =
    ReactJSX.LibraryManagedAttributes<C, P>;
  export type IntrinsicAttributes =
    ReactJSX.IntrinsicAttributes;
  export type IntrinsicClassAttributes<T> =
    ReactJSX.IntrinsicClassAttributes<T>;
}
