// Integration: the react-reconciler host config driving a real TermUi root,
// with painted output read back through a headless terminal emulator.
import { join } from "node:path";
import { readFile } from "node:fs/promises";
import { distDir } from "@term-ui/core/node";
import {
  type Element,
  InputManager,
} from "@term-ui/dom";
import { Terminal } from "@xterm/headless";
import {
  Suspense,
  useState,
  startTransition,
} from "react";
import {
  ContinuousEventPriority,
  DiscreteEventPriority,
} from "react-reconciler/constants";
import { describe, expect, it } from "vitest";
import { TermUi } from "./TermUi";
import {
  inputEventPriority,
} from "./reconciler/reconciler";

const tick = (ms = 20) =>
  new Promise((resolve) =>
    setTimeout(resolve, ms),
  );

const createApp = async (
  node: React.ReactNode,
  { debug = false } = {},
) => {
  const term = new Terminal({
    cols: 40,
    rows: 12,
    allowProposedApi: true,
  });
  const writeStream = {
    write: (chunk: string) => {
      term.write(chunk);
      return true;
    },
    columns: 40,
    rows: 12,
    on: () => {},
    off: () => {},
  } as any;
  const readStream = {
    setRawMode: () => {},
    on: () => {},
    off: () => {},
    resume: () => {},
    pause: () => {},
  } as any;
  const tui = await TermUi.createRoot(node, {
    ...(debug
      ? {
          loader: async () =>
            readFile(
              join(distDir, "core-debug.wasm"),
            ),
        }
      : {}),
    writeStream,
    readStream,
    enableInputs: false,
    enableAlternateScreen: false,
    clearScreenBeforePaint: false,
    exitOnCtrlC: false,
    size: { width: 40, height: 12 },
  });
  await tick();
  const screen = async () => {
    // wait for xterm's async write queue to drain
    await new Promise<void>((resolve) =>
      term.write("", resolve),
    );
    const lines: string[] = [];
    for (let i = 0; i < 12; i++) {
      lines.push(
        term.buffer.active
          .getLine(i)
          ?.translateToString(true) ?? "",
      );
    }
    return lines.join("\n");
  };
  const doc = tui.document as any;
  const feed = async (bytes: string) => {
    const im: InputManager =
      doc.testInputManager ??
      (doc.testInputManager = new InputManager(
        doc.module,
        readStream,
        doc.tree,
      ));
    if (!doc.testInputSubscribed) {
      doc.testInputSubscribed = true;
      im.subscribe((event: any) =>
        doc.onInput(event),
      );
    }
    im.buffer.appendSlice(
      new TextEncoder().encode(bytes),
    );
    im.consumeEvents();
    await tick();
  };
  return { tui, doc, screen, feed };
};

describe("mount / update / reorder / unmount", () => {
  it("mounts, updates state, reorders keyed children, unmounts", async () => {
    let setOrder!: (order: string[]) => void;
    let setShow!: (show: boolean) => void;
    const App = () => {
      const [order, so] = useState([
        "alpha",
        "beta",
      ]);
      const [show, ss] = useState(true);
      setOrder = so;
      setShow = ss;
      return (
        <view>
          {show && (
            <view>
              {order.map((key) => (
                <view key={key}>
                  <text>{`item ${key}`}</text>
                </view>
              ))}
            </view>
          )}
        </view>
      );
    };
    const { tui, screen } = await createApp(
      <App />,
    );
    let out = await screen();
    expect(out).toContain("item alpha");
    expect(out.indexOf("item alpha")).toBeLessThan(
      out.indexOf("item beta"),
    );

    setOrder(["beta", "alpha"]);
    await tick();
    out = await screen();
    expect(out.indexOf("item beta")).toBeLessThan(
      out.indexOf("item alpha"),
    );

    setShow(false);
    await tick();
    out = await screen();
    expect(out).not.toContain("item alpha");
    expect(out).not.toContain("item beta");
    tui.dispose();
  });

  it("unmounted instances are disposed (registry stays steady)", async () => {
    let setShow!: (show: boolean) => void;
    const App = () => {
      const [show, ss] = useState(false);
      setShow = ss;
      return (
        <view>
          <text>base</text>
          {show && (
            <view>
              {Array.from(
                { length: 8 },
                (_, i) => (
                  <view key={i}>
                    <text>{`row ${i}`}</text>
                  </view>
                ),
              )}
            </view>
          )}
        </view>
      );
    };
    const { tui, doc } = await createApp(
      <App />,
    );
    // one warm-up cycle so any lazily-created wrappers exist
    setShow(true);
    await tick();
    setShow(false);
    await tick(50);
    const baseline = doc.nodes.size;
    for (let i = 0; i < 5; i++) {
      setShow(true);
      await tick();
      setShow(false);
      await tick(50);
    }
    expect(doc.nodes.size).toBe(baseline);
    tui.dispose();
  });

  it("full lifecycle against the debug wasm leaves no leaks", async () => {
    let setCount!: (n: number) => void;
    const App = () => {
      const [count, sc] = useState(3);
      setCount = sc;
      return (
        <view>
          {Array.from(
            { length: count },
            (_, i) => (
              <view key={i}>
                <text>{`line ${i}`}</text>
              </view>
            ),
          )}
        </view>
      );
    };
    const { tui, doc } = await createApp(
      <App />,
      { debug: true },
    );
    const module = doc.module;
    for (const n of [6, 1, 8, 0, 4]) {
      setCount(n);
      await tick(30);
    }
    tui.dispose();
    await tick(50);
    expect(module.detectLeaks()).toBe(false);
  });
});

describe("commitUpdate diffing", () => {
  it("event handler identity swap: old stops firing, new fires", async () => {
    const calls: string[] = [];
    let setHandler!: (name: string) => void;
    const App = () => {
      const [name, sh] = useState("first");
      setHandler = sh;
      return (
        <view
          style={{
            width: "100%",
            height: "100%",
          }}
          onMouseDown={() => calls.push(name)}
        >
          <text>clickable</text>
        </view>
      );
    };
    const { tui, feed } = await createApp(
      <App />,
    );
    await feed("\x1b[<0;2;1M\x1b[<0;2;1m");
    expect(calls).toEqual(["first"]);
    setHandler("second");
    await tick();
    await feed("\x1b[<0;2;1M\x1b[<0;2;1m");
    expect(calls).toEqual(["first", "second"]);
    tui.dispose();
  });

  it("contentEditable toggles after mount", async () => {
    let setEditable!: (v: boolean) => void;
    const App = () => {
      const [editable, se] = useState(false);
      setEditable = se;
      return (
        <view contentEditable={editable}>
          <text>field</text>
        </view>
      );
    };
    const { tui, doc } = await createApp(
      <App />,
    );
    const el = doc.root.getChildren()[0] as Element;
    expect(
      el.getAttribute("contenteditable"),
    ).toBeFalsy();
    setEditable(true);
    await tick();
    expect(
      el.getAttribute("contenteditable"),
    ).toBe("true");
    setEditable(false);
    await tick();
    expect(
      el.getAttribute("contenteditable"),
    ).toBeFalsy();
    tui.dispose();
  });
});

describe("suspense", () => {
  it("re-suspension hides mounted content, resume restores it", async () => {
    let resolveGate!: () => void;
    let gateResolved = false;
    let gate: Promise<void> | null = null;
    let setBlocked!: (b: boolean) => void;
    const Gate = ({
      blocked,
    }: {
      blocked: boolean;
    }) => {
      if (blocked && !gateResolved) {
        gate ??= new Promise<void>((r) => {
          resolveGate = () => {
            gateResolved = true;
            r();
          };
        });
        throw gate;
      }
      return null;
    };
    const App = () => {
      const [blocked, sb] = useState(false);
      setBlocked = sb;
      return (
        <view>
          <text>always visible</text>
          <Suspense
            fallback={<text>loading fallback</text>}
          >
            <view>
              <text>suspense child</text>
            </view>
            <Gate blocked={blocked} />
          </Suspense>
        </view>
      );
    };
    const { tui, screen } = await createApp(
      <App />,
    );
    let out = await screen();
    expect(out).toContain("suspense child");

    setBlocked(true);
    await tick(50);
    out = await screen();
    expect(out).toContain("loading fallback");
    expect(out).not.toContain("suspense child");
    expect(out).toContain("always visible");

    resolveGate();
    // React throttles commits that replace a recently-shown fallback
    // (FALLBACK_THROTTLE_MS = 300); wait it out
    await tick(400);
    out = await screen();
    expect(out).toContain("suspense child");
    expect(out).not.toContain(
      "loading fallback",
    );
    tui.dispose();
  });
});

describe("transitions & priority", () => {
  it("startTransition update commits without crashing", async () => {
    let bump!: () => void;
    const App = () => {
      const [count, setCount] = useState(0);
      bump = () =>
        startTransition(() =>
          setCount((n) => n + 1),
        );
      return (
        <view>
          <text>{`count ${count}`}</text>
        </view>
      );
    };
    const { tui, screen } = await createApp(
      <App />,
    );
    bump();
    await tick(50);
    const out = await screen();
    expect(out).toContain("count 1");
    tui.dispose();
  });

  it("maps input events to update priorities", () => {
    expect(
      inputEventPriority({
        kind: "key",
      } as any),
    ).toBe(DiscreteEventPriority);
    expect(
      inputEventPriority({
        kind: "mouse",
        action: "press",
      } as any),
    ).toBe(DiscreteEventPriority);
    expect(
      inputEventPriority({
        kind: "mouse",
        action: "release",
      } as any),
    ).toBe(DiscreteEventPriority);
    expect(
      inputEventPriority({
        kind: "mouse",
        action: "motion",
      } as any),
    ).toBe(ContinuousEventPriority);
    expect(
      inputEventPriority({
        kind: "mouse",
        action: "wheel_down",
      } as any),
    ).toBe(ContinuousEventPriority);
  });

  it("click-handler state updates paint through the priority bracket", async () => {
    let clicks = 0;
    const App = () => {
      const [count, setCount] = useState(0);
      return (
        <view
          style={{
            width: "100%",
            height: "100%",
          }}
          onMouseDown={() => {
            clicks++;
            setCount((n) => n + 1);
          }}
        >
          <text>{`clicked ${count}`}</text>
        </view>
      );
    };
    const { tui, screen, feed } = await createApp(
      <App />,
    );
    await feed("\x1b[<0;2;1M\x1b[<0;2;1m");
    expect(clicks).toBe(1);
    const out = await screen();
    expect(out).toContain("clicked 1");
    tui.dispose();
  });
});
