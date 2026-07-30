#!/usr/bin/env bash
# Clean-room install check: pack the published packages, install the tarballs
# into a throwaway project outside the repo, and run the README quickstart.
#
# This is the gate before publishing — it catches missing `files` entries, bad
# `exports` maps, and dependencies that are declared dev-only but imported at
# runtime (none of which the in-repo build can catch, because pnpm's workspace
# links paper over all three).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> building workspace"
cd "$REPO"
pnpm build >/dev/null

echo "==> packing packages"
# MUST be `pnpm pack`, not `npm pack`: pnpm rewrites the `workspace:*` and
# `catalog:` protocols into real version ranges on the way out. npm leaves them
# verbatim, producing a tarball no consumer can install
# (EUNSUPPORTEDPROTOCOL). The same applies at publish time — use `pnpm publish`.
mkdir -p "$WORK/tarballs"
for pkg in shared core dom react; do
  (cd "$REPO/packages/$pkg" && pnpm pack --pack-destination "$WORK/tarballs" >/dev/null)
done
ls "$WORK/tarballs"

echo "==> creating scratch project at $WORK/app"
mkdir -p "$WORK/app/src"
cd "$WORK/app"
cat > package.json <<'JSON'
{
  "name": "clean-room-app",
  "private": true,
  "type": "module",
  "version": "1.0.0"
}
JSON

# install with npm on purpose: no workspace links, no pnpm store, nothing that
# could paper over a missing dependency — closest thing to a real consumer
npm install --silent --no-audit --no-fund \
  "$WORK"/tarballs/term-ui-shared-*.tgz \
  "$WORK"/tarballs/term-ui-core-*.tgz \
  "$WORK"/tarballs/term-ui-dom-*.tgz \
  "$WORK"/tarballs/term-ui-react-*.tgz \
  react tsx typescript @types/react @types/node >/dev/null

echo "==> writing the README quickstart"
# kept in sync with packages/react/README.md; if this drifts, the README is wrong
cat > src/app.tsx <<'TSX'
import { useState } from "react";
import TermUi from "@term-ui/react";

const App = () => {
  const [count] = useState(0);
  return (
    <view
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        borderStyle: "rounded",
        borderColor: "cyan",
      }}
    >
      <text style={{ color: "cyan", fontWeight: "bold" }}>
        Count: {count}
      </text>
      <view style={{ borderStyle: "double", padding: 1 }}>
        <text>Click to increment</text>
      </view>
    </view>
  );
};

// README quickstart ends at `TermUi.createRoot(<App />, {})`; the harness
// keeps the render on the main screen buffer so it can be read back, and
// tears down after a beat so the run terminates.
const tui = await TermUi.createRoot(<App />, {
  enableAlternateScreen: false,
  clearScreenBeforePaint: false,
});
setTimeout(() => tui.dispose(), 800);
TSX

cat > tsconfig.json <<'JSON'
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "jsxImportSource": "@term-ui/react",
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
JSON

echo "==> type-checking the quickstart (proves the shipped types work)"
npx tsc --noEmit -p tsconfig.json

echo "==> running under a pty"
python3 "$REPO/scripts/clean-room-run.py" "$WORK/app"

echo
echo "clean-room check PASSED"
