// Integration: wheel/keyboard scrolling and geometry consistency under
// scroll, driven by raw terminal bytes through InputManager -> Document.
import { initFromFile } from "@term-ui/core/node";
import { describe, expect, it } from "vitest";
import { Document } from "./Document";
import type { Element } from "./Element";
import { InputManager } from "./InputManager";

const module = await initFromFile(undefined);

const fakeWriteStream = {
  write: () => true,
  columns: 30,
  rows: 12,
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

// content: a 20x4 scroll container at the top-left holding 8 lines
const setup = () => {
  const doc = new Document(module, {
    enableInputs: false,
    enableAlternateScreen: false,
    clearScreenBeforePaint: false,
    exitOnCtrlC: false,
    writeStream: fakeWriteStream,
    readStream: fakeReadStream,
    size: { width: 30, height: 12 },
  });
  doc.root.setStyle("width: 30px; height: 12px;");
  const pane = doc.createElement(
    "view",
    "width: 20px; height: 4px; overflow: scroll;",
  );
  pane.setAttribute("contenteditable", "true");
  doc.root.appendChild(pane);
  const lines: Element[] = [];
  for (let i = 1; i <= 8; i++) {
    const row = doc.createElement("view", "");
    row.appendChild(
      doc.createTextNode(`line ${i}`),
    );
    pane.appendChild(row);
    lines.push(row);
  }
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
  return { doc, pane, feed };
};

// SGR wheel: 64 = up, 65 = down
const wheelDown = (col: number, row: number) =>
  `\x1b[<65;${col};${row}M`;
const wheelUp = (col: number, row: number) =>
  `\x1b[<64;${col};${row}M`;

describe("wheel scrolling", () => {
  it("wheel over the pane scrolls it, clamped", async () => {
    const { pane, feed } = setup();
    expect(pane.scrollTopMax).toBe(4); // 8 lines - 4 client
    let scrollEvents = 0;
    pane.addEventListener("scroll", () => {
      scrollEvents++;
    });
    await feed(wheelDown(3, 2));
    expect(pane.scrollTop).toBe(1);
    expect(scrollEvents).toBe(1);
    await feed(wheelUp(3, 2));
    await feed(wheelUp(3, 2));
    expect(pane.scrollTop).toBe(0); // clamped at 0
    for (let i = 0; i < 10; i++) {
      await feed(wheelDown(3, 2));
    }
    expect(pane.scrollTop).toBe(4); // clamped at max
  });

  it("wheel outside the pane does not scroll it", async () => {
    const { pane, feed } = setup();
    await feed(wheelDown(25, 10)); // over root, which is not scrollable
    expect(pane.scrollTop).toBe(0);
  });

  it("preventDefault on wheel blocks scrolling", async () => {
    const { doc, pane, feed } = setup();
    doc.addEventListener("wheel", (event) => {
      event.preventDefault();
    });
    await feed(wheelDown(3, 2));
    expect(pane.scrollTop).toBe(0);
  });
});

describe("geometry under scroll", () => {
  it("click lands on the scrolled line", async () => {
    const { doc, pane, feed } = setup();
    pane.scrollTo(0, 2);
    doc.computeLayout();
    doc.paint();
    // top visible row is now "line 3"
    await feed(`\x1b[<0;2;1M`);
    const focus = doc.selection!.getFocus();
    const text = doc.getElement(focus.node);
    expect(
      (text as any).getText(),
    ).toBe("line 3");
  });

  it("clipped-out content is not hit", async () => {
    const { doc, pane } = setup();
    pane.scrollTo(0, 2);
    doc.computeLayout();
    doc.paint();
    // rows 5..12 of the viewport are outside the pane; a hit test there
    // must not resolve to any of the pane's lines
    const hits = module.Tree_hitTestList(
      doc.tree.ptr,
      2,
      6,
      0b0101,
    );
    for (const hit of hits) {
      const el = doc.getElement(hit.id);
      if (el && (el as any).getText) {
        expect(
          (el as any).getText(),
        ).not.toMatch(/^line/);
      }
    }
  });
});

describe("keyboard scrolling", () => {
  it("PgDn/PgUp scroll the hovered scroll container by a page", async () => {
    const { pane, feed } = setup();
    // hover the pane so it becomes the active scroll container
    await feed("\x1b[<35;3;2M");
    await feed("\x1b[5;1~".replace("5;1", "6")); // \x1b[6~ = PgDn
    expect(pane.scrollTop).toBe(4); // one page = clientHeight 4, clamped to max
    await feed("\x1b[5~"); // PgUp
    expect(pane.scrollTop).toBe(0);
  });

  it("PgDn scrolls the container owning the selection anchor", async () => {
    const { doc, pane, feed } = setup();
    await feed("\x1b[<0;2;1M"); // click into "line 1" inside the pane
    await feed("\x1b[<0;2;1m");
    expect(doc.selection).toBeTruthy();
    await feed("\x1b[6~");
    expect(pane.scrollTop).toBe(4);
  });
});

describe("caret visibility", () => {
  it("arrow past the fold scrolls the caret into view", async () => {
    const { doc, pane, feed } = setup();
    await feed("\x1b[<0;2;1M"); // caret in "line 1" (top row)
    await feed("\x1b[<0;2;1m");
    expect(pane.scrollTop).toBe(0);
    // 5 x down-arrow: caret walks to "line 6", two rows past the fold
    for (let i = 0; i < 5; i++) {
      await feed("\x1b[B");
    }
    expect(pane.scrollTop).toBe(2);
    // and back up to the top
    for (let i = 0; i < 5; i++) {
      await feed("\x1b[A");
    }
    expect(pane.scrollTop).toBe(0);
  });
});

describe("multiple scrollable sections", () => {
  // two sibling panes side by side, plus a scrollable box nested in the right pane
  const setupMulti = () => {
    const doc = new Document(module, {
      enableInputs: false,
      enableAlternateScreen: false,
      clearScreenBeforePaint: false,
      exitOnCtrlC: false,
      writeStream: fakeWriteStream,
      readStream: fakeReadStream,
      size: { width: 30, height: 12 },
    });
    doc.root.setStyle(
      "width: 30px; height: 12px; display: flex;",
    );
    const makePane = (style: string) => {
      const pane = doc.createElement(
        "view",
        style,
      );
      doc.root.appendChild(pane);
      return pane;
    };
    const fill = (
      el: Element,
      prefix: string,
      n: number,
    ) => {
      for (let i = 1; i <= n; i++) {
        const row = doc.createElement("view", "");
        row.appendChild(
          doc.createTextNode(`${prefix} ${i}`),
        );
        el.appendChild(row);
      }
    };
    const left = makePane(
      "width: 12px; height: 6px; overflow: scroll;",
    );
    fill(left, "left", 12);
    const right = makePane(
      "width: 14px; height: 10px; overflow: scroll;",
    );
    const inner = doc.createElement(
      "view",
      "width: 12px; height: 3px; overflow: scroll;",
    );
    fill(inner, "in", 8);
    right.appendChild(inner);
    fill(right, "right", 14);
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
    return { doc, left, right, inner, feed };
  };

  it("wheel scrolls only the pane under the pointer", async () => {
    const { left, right, inner, feed } =
      setupMulti();
    await feed(wheelDown(3, 3)); // over left pane
    expect(left.scrollTop).toBe(1);
    expect(right.scrollTop).toBe(0);
    expect(inner.scrollTop).toBe(0);
    // right pane starts at x=13 (after left width 12); wheel over its
    // lower rows, below the nested inner box
    await feed(wheelDown(20, 8));
    expect(left.scrollTop).toBe(1);
    expect(right.scrollTop).toBe(1);
    expect(inner.scrollTop).toBe(0);
  });

  it("nested pane wins over its ancestor, then chains at the edge", async () => {
    const { right, inner, feed } = setupMulti();
    // inner box occupies the right pane's top rows
    await feed(wheelDown(15, 2));
    expect(inner.scrollTop).toBe(1);
    expect(right.scrollTop).toBe(0);
    // exhaust the inner pane exactly (max = 8 - 3 = 5; already at 1)
    for (let i = 0; i < 4; i++) {
      await feed(wheelDown(15, 2));
    }
    expect(inner.scrollTop).toBe(5);
    expect(right.scrollTop).toBe(0);
    // inner is at its edge: further wheel chains to the ancestor
    await feed(wheelDown(15, 2));
    expect(inner.scrollTop).toBe(5);
    expect(right.scrollTop).toBe(1);
  });

  it("wheel-up chains independently of wheel-down state", async () => {
    const { right, inner, feed } = setupMulti();
    // inner at top: wheel-up over it cannot scroll it, chains to right pane
    right.scrollTo(0, 2);
    await feed(wheelUp(15, 2));
    expect(inner.scrollTop).toBe(0);
    expect(right.scrollTop).toBe(1);
  });
});

describe("event bursts", () => {
  it("a burst of wheel events in one chunk all apply", async () => {
    const { pane, feed } = setup();
    // three wheels in a single buffer chunk, like a fast trackpad flick
    await feed(wheelDown(3, 2) + wheelDown(3, 2) + wheelDown(3, 2));
    expect(pane.scrollTop).toBe(3);
  });

  it("a burst of arrow keys in one chunk all apply", async () => {
    const { doc, feed } = setup();
    await feed("\x1b[<0;1;1M");
    await feed("\x1b[<0;1;1m");
    // three right-arrows (kitty CSI) in one chunk, like key autorepeat
    await feed("\x1b[C\x1b[C\x1b[C");
    expect(doc.selection!.getFocus().offset).toBe(3);
  });
});
