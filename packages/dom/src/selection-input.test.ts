// Integration: raw terminal bytes -> InputManager -> Document events ->
// wasm selection state. Covers click-to-caret, drag-to-select, and
// keyboard move/extend/word defaults.
// Event delivery is deferred via setTimeout, so each feed awaits a tick.
import { initFromFile } from "@term-ui/core/node";
import { describe, expect, it } from "vitest";
import { Document } from "./Document";
import { InputManager } from "./InputManager";

const module = await initFromFile(undefined);

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

const setup = (editable = false) => {
  const doc = new Document(module, {
    enableInputs: false,
    enableAlternateScreen: false,
    clearScreenBeforePaint: false,
    exitOnCtrlC: false,
    writeStream: fakeWriteStream,
    readStream: fakeReadStream,
    size: { width: 20, height: 10 },
  });
  doc.root.setStyle("width: 20px;");
  if (editable) {
    doc.root.setAttribute(
      "contenteditable",
      "true",
    );
  }
  const text = doc.createTextNode(
    "hello world here",
  );
  doc.root.appendChild(text);
  doc.computeLayout();
  doc.paint();

  const im = new InputManager(
    module,
    fakeReadStream,
    doc.tree,
  );
  im.subscribe((event) =>
    (doc as any).onInput(event),
  );
  const feed = async (bytes: string) => {
    im.buffer.appendSlice(
      new TextEncoder().encode(bytes),
    );
    im.consumeEvents();
    await tick();
  };
  return { doc, feed, text };
};

// SGR mouse: \x1b[<0;COL;ROW M(press) / m(release), 1-based coordinates
const press = (col: number, row: number) =>
  `\x1b[<0;${col};${row}M`;
const move = (col: number, row: number) =>
  `\x1b[<32;${col};${row}M`;
const release = (col: number, row: number) =>
  `\x1b[<0;${col};${row}m`;

describe("selection input integration", () => {
  it("click places the caret", async () => {
    const { doc, feed } = setup();
    // "hello world here": click on the cell of 'o' in "world" -> caret at 7
    await feed(press(8, 1));
    const selection = doc.selection;
    expect(selection).toBeTruthy();
    expect(selection!.getFocus().offset).toBe(7);
    expect(selection!.isCollapsed()).toBe(true);
  });

  it("drag extends the selection", async () => {
    const { doc, feed } = setup();
    await feed(press(1, 1)); // caret at start of "hello"
    await feed(move(6, 1)); // drag to after "hello"
    await feed(release(6, 1));
    const selection = doc.selection!;
    expect(selection.isCollapsed()).toBe(false);
    expect(selection.getAnchor().offset).toBe(0);
    expect(selection.getFocus().offset).toBe(5);
  });

  it("shift+arrow extends, plain arrow moves", async () => {
    const { doc, feed } = setup();
    await feed(press(1, 1)); // collapsed caret at 0
    await feed("\x1b[1;2C"); // shift+right -> extend
    const selection = doc.selection!;
    expect(selection.getAnchor().offset).toBe(0);
    expect(selection.getFocus().offset).toBe(1);
    await feed("\x1b[C"); // plain right -> collapse to edge
    expect(selection.isCollapsed()).toBe(true);
    expect(selection.getFocus().offset).toBe(1);
  });

  it("word modifier moves by word", async () => {
    const { doc, feed } = setup();
    await feed(press(1, 1)); // caret at 0
    await feed("\x1b[1;3C"); // alt+right -> word forward
    const selection = doc.selection!;
    expect(selection.isCollapsed()).toBe(true);
    // end of "hello"
    expect(selection.getFocus().offset).toBe(5);
  });
});

describe("editing keys", () => {
  it("backspace deletes backward (kitty and legacy encodings)", async () => {
    const { doc, feed, text } = setup(true);
    await feed(press(8, 1)); // caret at offset 7, between 'w' and 'o'
    await feed("\x7f"); // legacy backspace: removes 'w'
    expect(text.getText()).toBe(
      "hello orld here",
    );
    await feed("\x1b[127u"); // kitty-protocol backspace: removes ' '
    expect(text.getText()).toBe(
      "helloorld here",
    );
    expect(
      doc.selection!.getFocus().offset,
    ).toBe(5);
  });

  it("delete removes the next character", async () => {
    const { doc, feed, text } = setup(true);
    await feed(press(1, 1)); // caret at 0
    await feed("\x1b[3~"); // delete key
    expect(text.getText()).toBe(
      "ello world here",
    );
    expect(
      doc.selection!.getFocus().offset,
    ).toBe(0);
  });

  it("backspace does nothing outside editable regions", async () => {
    const { feed, text } = setup(false);
    await feed(press(8, 1));
    await feed("\x7f");
    expect(text.getText()).toBe(
      "hello world here",
    );
  });
});

describe("drag state machine", () => {
  it("moving after release does not extend the selection", async () => {
    const { doc, feed } = setup();
    await feed(press(1, 1));
    await feed(release(1, 1));
    await feed(move(8, 1)); // plain move, button up
    const selection = doc.selection!;
    expect(selection.isCollapsed()).toBe(true);
    expect(selection.getFocus().offset).toBe(0);
  });

  it("a missed release is healed by button-less motion", async () => {
    const { doc, feed } = setup();
    await feed(press(1, 1));
    // release never arrives (e.g. happened outside the window);
    // any-event tracking then reports motion with no button (code 35)
    await feed("\x1b[<35;4;1M");
    await feed(move(8, 1)); // held-button motion encoding, but state is healed
    const selection = doc.selection!;
    expect(selection.isCollapsed()).toBe(true);
  });

  it("drag extends while held and stops after release", async () => {
    const { doc, feed } = setup();
    await feed(press(1, 1));
    await feed(move(4, 1)); // genuine drag while held
    expect(doc.selection!.isCollapsed()).toBe(false);
    expect(doc.selection!.getFocus().offset).toBe(3);
    await feed(release(4, 1));
    await feed(move(8, 1));
    expect(doc.selection!.getFocus().offset).toBe(3);
  });
});
