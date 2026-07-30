// Input-stream robustness: the engine must survive and correctly apply
// event streams that arrive split at arbitrary chunk boundaries (fast
// wheel flicks, autorepeat), including garbage bytes — a terminal is an
// untrusted byte source. Runs against the debug wasm so panics are loud.
import { join } from "node:path";
import {
  distDir,
  initFromFile,
} from "@term-ui/core/node";
import { describe, expect, it } from "vitest";
import { Document } from "./Document";
import { InputManager } from "./InputManager";

const module = await initFromFile(
  join(distDir, "core-debug.wasm"),
);
const ws = {
  write: () => true,
  columns: 60,
  rows: 20,
  on: () => {},
  off: () => {},
} as any;
const rs = {
  setRawMode: () => {},
  on: () => {},
  off: () => {},
  resume: () => {},
  pause: () => {},
} as any;

const setup = () => {
  const doc = new Document(module, {
    enableInputs: false,
    enableAlternateScreen: false,
    clearScreenBeforePaint: false,
    exitOnCtrlC: false,
    writeStream: ws,
    readStream: rs,
    size: { width: 60, height: 20 },
  });
  doc.root.setStyle("width: 60px; height: 20px;");
  const pane = doc.createElement(
    "view",
    "width: 40px; height: 10px; overflow: scroll;",
  );
  doc.root.appendChild(pane);
  for (let i = 0; i < 30; i++) {
    const row = doc.createElement("view", "");
    row.appendChild(
      doc.createTextNode(`row ${i}`),
    );
    pane.appendChild(row);
  }
  doc.computeLayout();
  doc.paint();
  const im = new InputManager(
    module,
    rs,
    doc.tree,
  );
  im.subscribe((e) =>
    (doc as any).onInput(e),
  );
  return { doc, pane, im };
};

const enc = new TextEncoder();
const tick = () =>
  new Promise((r) => setTimeout(r, 20));

/**
 * Wait until `predicate` holds, polling the macrotask queue.
 *
 * Events are delivered through a batched `setTimeout(…, 0)` flush, and each
 * dispatch drags layout and paint along with it. A fixed sleep therefore races
 * the pipeline: it passes on an idle machine and fails when the box is busy.
 * Waiting on the condition itself is both faster in the common case and stable
 * under load — the timeout only bounds an outright failure.
 */
const waitFor = async (
  predicate: () => boolean,
  message: string,
  timeoutMs = 3000,
) => {
  const deadline = Date.now() + timeoutMs;
  while (!predicate()) {
    if (Date.now() > deadline) {
      throw new Error(
        `timed out after ${timeoutMs}ms waiting for ${message}`,
      );
    }
    await tick();
  }
};

describe("input robustness", () => {
  it("wheel streams split at every chunk size apply fully", async () => {
    // 20 wheel-downs per chunk size; pane max is 20, so each pass pins
    // scrollTop to max regardless of how the stream was split
    const seqDown = "\x1b[<65;5;3M";
    const seqUp = "\x1b[<64;5;3M";
    for (let chunk = 1; chunk <= 21; chunk++) {
      const { pane, im } = setup();
      const stream = seqDown.repeat(25);
      for (
        let i = 0;
        i < stream.length;
        i += chunk
      ) {
        im.buffer.appendSlice(
          enc.encode(stream.slice(i, i + chunk)),
        );
        im.consumeEvents();
      }
      await waitFor(
        () =>
          pane.scrollTop === pane.scrollTopMax,
        `scrollTop to reach max with chunk size ${chunk}`,
      );
      expect(pane.scrollTop).toBe(
        pane.scrollTopMax,
      );
      // and back up, also split
      const upStream = seqUp.repeat(25);
      for (
        let i = 0;
        i < upStream.length;
        i += chunk
      ) {
        im.buffer.appendSlice(
          enc.encode(
            upStream.slice(i, i + chunk),
          ),
        );
        im.consumeEvents();
      }
      await waitFor(
        () => pane.scrollTop === 0,
        `scrollTop to return to 0 with chunk size ${chunk}`,
      );
      expect(pane.scrollTop).toBe(0);
      im.dispose();
    }
  });

  it("garbage bytes between sequences do not crash and events still apply", async () => {
    const { pane, im } = setup();
    const garbage = new Uint8Array([
      0xff, 0xfe, 0x80, 0x9a,
    ]);
    for (let i = 0; i < 5; i++) {
      im.buffer.appendSlice(garbage);
      im.buffer.appendSlice(
        enc.encode("\x1b[<65;5;3M"),
      );
      im.consumeEvents();
    }
    await waitFor(
      () => pane.scrollTop === 5,
      "all 5 wheel events to apply despite interleaved garbage",
    );
    expect(pane.scrollTop).toBe(5);
  });
});

describe("event batching (scroll responsiveness)", () => {
  it("a burst chunk produces one coalesced render pass, and a trailing reversal applies in it", async () => {
    const doc = new Document(module, {
      enableInputs: false,
      enableAlternateScreen: false,
      clearScreenBeforePaint: false,
      exitOnCtrlC: false,
      writeStream: ws,
      readStream: rs,
      size: { width: 60, height: 20 },
    });
    doc.root.setStyle("width: 60px; height: 20px;");
    const pane = doc.createElement(
      "view",
      "width: 40px; height: 10px; overflow: scroll;",
    );
    doc.root.appendChild(pane);
    for (let i = 0; i < 30; i++) {
      const row = doc.createElement("view", "");
      row.appendChild(
        doc.createTextNode(`row ${i}`),
      );
      pane.appendChild(row);
    }
    doc.computeLayout();
    doc.paint();

    // mimic TermUi's microtask paint coalescing and count real renders
    let renders = 0;
    let scheduled = false;
    (doc as any).onPaintRequest = () => {
      if (scheduled) return;
      scheduled = true;
      queueMicrotask(() => {
        scheduled = false;
        renders++;
      });
    };

    const im = new InputManager(
      module,
      rs,
      doc.tree,
    );
    im.subscribe((e) =>
      (doc as any).onInput(e),
    );

    // 10 wheel-downs then an immediate reversal, all in one chunk — like
    // flicking and then scrolling back
    im.buffer.appendSlice(
      enc.encode(
        "\x1b[<65;5;3M".repeat(10) +
          "\x1b[<64;5;3M",
      ),
    );
    im.consumeEvents();
    // wait for the burst to land, not for a fixed duration — the render count
    // is unaffected by waiting longer, since coalescing is per flush and no
    // further input arrives
    await waitFor(
      () => pane.scrollTop === 9,
      "the burst (10 down, 1 up) to apply",
    );

    // all 11 events applied: net 10 down - 1 up = 9
    expect(pane.scrollTop).toBe(9);
    // and the whole burst cost a single coalesced render pass
    expect(renders).toBe(1);
    im.dispose();
  });
});
