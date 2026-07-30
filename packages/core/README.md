# @term-ui/core

The term-ui engine: a miniature browser engine for the terminal, written in Zig and compiled to WebAssembly, with a thin TypeScript wrapper.

This package is the bottom of the stack. Most applications should use [`@term-ui/react`](https://www.npmjs.com/package/@term-ui/react) (React) or [`@term-ui/dom`](https://www.npmjs.com/package/@term-ui/dom) (imperative DOM-style API) instead of talking to it directly.

## What's in here

The same pipeline a browser runs, sized for a terminal:

- **DOM tree** — nodes, attributes, styles
- **Layout tree** — block and flex layout with anonymous boxes, mirroring the resolved DOM
- **Text pipeline** — CSS whitespace rules, wrapping, alignment, grapheme-aware widths
- **Render list** — the paint-order display list, with clipping and scroll offsets
- **Renderer** — diffing painter that only rewrites the cells that changed
- **Selection** — WebKit-style caret-from-point, ranges, word and line granularity
- **Terminal input** — kitty keyboard protocol, SGR mouse, legacy fallbacks, parsed into events

## Usage

```ts
import { init } from "@term-ui/core";
import { loader } from "@term-ui/core/node";

const module = await init({ loader });
```

`module` is the instantiated WASM export surface. Entry points:

| Entry | Contents |
|---|---|
| `@term-ui/core` | `init`, the `Module` type, shared types |
| `@term-ui/core/node` | Node loaders (`loader`, `initFromFile`, `distDir`) |
| `@term-ui/core/constants` | Enums shared with the engine (hit-test filters, event codes) |
| `@term-ui/core/core.wasm` | Release build, for custom loaders |
| `@term-ui/core/core-debug.wasm` | Debug build with allocation tracking and leak detection |

## Memory

The engine owns its allocations. Values crossing the boundary are copied into JS
before the next call, so returned strings and arrays are safe to hold; handles
such as trees and selections are disposed explicitly by their owner. The debug
build tracks every allocation, so a test can assert a session leaked nothing.

## Building from source

Requires Zig at the version pinned in `.zigversion` at the repo root — the code
tracks Zig master, so the pin is exact and deliberate.

```bash
pnpm build:wasm:all   # debug + release builds into dist/
zig build test        # engine test suite
```

## License

MIT — see [LICENSE](LICENSE).
