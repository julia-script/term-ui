# @term-ui/dom

## 0.1.0

### Minor Changes

- First release of the rebuilt engine.

  **Engine**

  - Layout, paint, selection and terminal input rebuilt on current Zig, with a spec'd
    behavior contract and a test suite covering invalidation, layout/paint snapshots,
    memory leaks and input robustness.
  - Scrollable regions anywhere on screen, with wheel routing, scroll chaining and
    keyboard paging.
  - Browser-style selection: caret-from-point, drag-to-select across wrapped lines,
    word and line granularity.
  - Text input handles held-key autorepeat, preserved line breaks, and caret
    navigation through empty lines.

  **React**

  - Renderer rebuilt on `react-reconciler` 0.33 / React 19.2: host instances are
    released on unmount, Suspense hides and restores mounted content, transitions
    commit, and updates are scheduled at a priority derived from the input that
    caused them.
  - `<view>` and `<text>` are properly typed. Set `"jsxImportSource": "@term-ui/react"`
    in tsconfig — without it, TypeScript resolves them to React's SVG elements.
    This replaces the removed `<term-view>` / `<term-text>` element names.

  **Packaging**

  - Dependencies now reflect what the code imports. `@term-ui/core` and
    `@term-ui/shared` were previously dev-only despite being imported at runtime,
    so a clean install of `@term-ui/dom` or `@term-ui/react` could fail.
  - Removed the unfinished devtools integration from `@term-ui/dom`, along with the
    `dev` Document option and its tRPC/ws/zod dependencies.

### Patch Changes

- Updated dependencies
  - @term-ui/core@0.1.0
  - @term-ui/shared@0.1.0

## 0.0.2

### Patch Changes

- 5bce9b4: Optimize rendering by just rendering diff

## 0.0.1

### Patch Changes

- 08db300: improved README documentation
