// Leak gate: a full document lifecycle against the DEBUG wasm build must
// leave zero surviving allocations after dispose. This is the boundary
// counterpart of core's steady-state churn test.
import { join } from "node:path";
import {
  distDir,
  initFromFile,
} from "@term-ui/core/node";
import { describe, expect, it } from "vitest";
import { Document } from "./Document";
import { InputManager } from "./InputManager";

// explicit path: initFromFile memoizes on its first argument, so this
// loads the debug build without colliding with the release module used
// by the other test files
const debugModule = await initFromFile(
  join(distDir, "core-debug.wasm"),
);

const fakeWriteStream = {
  write: () => true,
  columns: 40,
  rows: 10,
  on: () => {},
  off: () => {},
} as any;

const fakeReadStream = {
  setRawMode: () => {},
  on: () => {},
  off: () => {},
  resume: () => {},
  pause: () => {},
} as any;

const tick = () =>
  new Promise((resolve) =>
    setTimeout(resolve, 5),
  );

describe("memory boundary", () => {
  it("full lifecycle leaves no surviving allocations", async () => {
    const doc = new Document(debugModule, {
      enableInputs: false,
      enableAlternateScreen: false,
      clearScreenBeforePaint: false,
      exitOnCtrlC: false,
      writeStream: fakeWriteStream,
      readStream: fakeReadStream,
      size: { width: 20, height: 10 },
    });
    doc.root.setStyle(
      "width: 20px; height: 10px;",
    );
    doc.root.setAttribute(
      "contenteditable",
      "true",
    );
    const text = doc.createTextNode(
      "hello world here",
    );
    doc.root.appendChild(text);

    const im = new InputManager(
      debugModule,
      fakeReadStream,
      doc.tree,
    );
    im.subscribe((event) =>
      (doc as any).onInput(event),
    );

    // exercise the transient-output exports and real mutation churn
    for (let i = 0; i < 20; i++) {
      text.setText(
        i % 2 ? "other content that wraps" : "hello world here",
      );
      doc.computeLayout();
      doc.paint();
      doc.tree.dump();
      text.getText();
      doc.root.getChildren();
      doc.caretPositionFromPoint(3, 0);
    }

    // click, drag, type, delete through the input pipeline
    im.buffer.appendSlice(
      new TextEncoder().encode("\x1b[<0;4;1M"),
    );
    im.consumeEvents();
    await tick();
    im.buffer.appendSlice(
      new TextEncoder().encode(
        "\x1b[<32;8;1M\x1b[<0;8;1m",
      ),
    );
    im.consumeEvents();
    await tick();
    im.buffer.appendSlice(
      new TextEncoder().encode("zz\x7f"),
    );
    im.consumeEvents();
    await tick();

    im.dispose();
    doc.dispose();

    expect(debugModule.detectLeaks()).toBe(
      false,
    );
  });
});
