/**
 * Development JSX runtime. Mirrors {@link "./jsx-runtime"} — TypeScript resolves
 * this entry instead when compiling with `jsx: "react-jsxdev"`.
 */
export {
  Fragment,
  jsxDEV,
} from "react/jsx-dev-runtime";

import type { JSX as ReactJSX } from "react/jsx-dev-runtime";
import type {
  TermTextProps,
  TermViewProps,
} from "./types.js";

export namespace JSX {
  export interface IntrinsicElements {
    view: TermViewProps;
    text: TermTextProps;
  }
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
