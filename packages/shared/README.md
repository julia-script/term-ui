# @term-ui/shared

Internal utilities shared between the term-ui packages: terminal escape
sequences, the kitty keyboard protocol handshake, cursor shapes, and small
helpers (`assert`, `clamp`, `raise`, string encoding, common types).

This package exists so [`@term-ui/core`](https://www.npmjs.com/package/@term-ui/core),
[`@term-ui/dom`](https://www.npmjs.com/package/@term-ui/dom) and
[`@term-ui/react`](https://www.npmjs.com/package/@term-ui/react) can agree on
those definitions. **It has no stable public API** — modules may be renamed,
moved, or removed in any release. Depend on it only through the packages above.

Every module is exported by path:

```ts
import * as sequences from "@term-ui/shared/cmd/sequences";
import { raise } from "@term-ui/shared/raise";
```

## License

MIT — see [LICENSE](LICENSE).
