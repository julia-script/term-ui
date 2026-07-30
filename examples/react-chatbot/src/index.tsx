// AI chatbot demo: a scrollable conversation pane, an editable input box,
// and streaming responses re-rendering per token through the reconciler.
//
//   pnpm start            (in examples/react-chatbot)
//
// Uses OPENROUTER_API_KEY or OPENAI_API_KEY from the environment; without a
// key it falls back to a canned demo bot so the UI always runs.
//   Enter: send · Esc: stop streaming · click the input to move the caret
import type {
  Element,
  KeyboardEvent,
} from "@term-ui/dom";
import { TextElement } from "@term-ui/dom";
import TermUi, { useTermUi } from "@term-ui/react";
import {
  memo,
  useEffect,
  useRef,
  useState,
} from "react";
import {
  type ChatMessage,
  pickBackend,
} from "./llm.js";

const backend = pickBackend();

type Status =
  | "idle"
  | "thinking"
  | "streaming"
  | "error";

const statusLabel: Record<Status, string> = {
  idle: "ready · Enter to send",
  thinking: "thinking…",
  streaming: "streaming · Esc to stop",
  error: "error · Enter to retry",
};

const roleColor = (role: ChatMessage["role"]) =>
  role === "user" ? "cyan" : "green";
const roleLabel = (role: ChatMessage["role"]) =>
  role === "user" ? "you" : "bot";

const MessageRow = memo(
  ({ message }: { message: ChatMessage }) => (
    <view style={{ padding: "0 1" }}>
      <text
        style={{ color: roleColor(message.role) }}
      >
        {`${roleLabel(message.role)}: `}
      </text>
      <text style={{ color: "white" }}>
        {message.content}
      </text>
    </view>
  ),
);

// Uncontrolled on purpose: the engine owns the editable's content (typing,
// caret, selection); React must never re-render its children or it would
// clobber what the user typed. Read/clear happens imperatively via the ref.
const InputBox = memo(
  ({
    inputRef,
  }: {
    inputRef: React.RefObject<Element | null>;
  }) => (
    <view
      // biome-ignore lint/suspicious/noExplicitAny: view JSX types are SVG-typed today
      ref={inputRef as any}
      {...({ contentEditable: true } as object)}
      style={{
        width: "100%",
        height: "4",
        borderStyle: "double",
        borderColor: "cyan",
        padding: "0 1",
        color: "white",
      }}
    />
  ),
  () => true,
);

const App = () => {
  const termUi = useTermUi();
  const [messages, setMessages] = useState<
    ChatMessage[]
  >([]);
  const [status, setStatus] =
    useState<Status>("idle");
  const inputRef = useRef<Element | null>(null);
  const historyRef = useRef<Element | null>(null);
  const messagesRef = useRef(messages);
  messagesRef.current = messages;
  const busyRef = useRef(false);
  const abortRef =
    useRef<AbortController | null>(null);

  const focusInput = () => {
    const input = inputRef.current;
    if (!input || !termUi) return;
    const textChild = input
      .getChildren()
      .find(
        (child): child is TextElement =>
          child instanceof TextElement,
      );
    if (!textChild) return;
    termUi.document.createSelection({
      node: textChild.id,
      offset: textChild.getText().length,
    });
    termUi.document.requestPaint();
  };

  const readDraft = () =>
    inputRef.current
      ?.getChildren()
      .map((child) =>
        child instanceof TextElement
          ? child.getText()
          : "",
      )
      .join("") ?? "";

  const clearInput = () => {
    inputRef.current?.setText("");
    focusInput();
  };

  const send = async () => {
    if (busyRef.current) return;
    const draft = readDraft().trim();
    if (!draft) return;
    busyRef.current = true;
    clearInput();
    const history: ChatMessage[] = [
      ...messagesRef.current,
      { role: "user", content: draft },
    ];
    setMessages([
      ...history,
      { role: "assistant", content: "" },
    ]);
    setStatus("thinking");
    const controller = new AbortController();
    abortRef.current = controller;
    const appendToReply = (chunk: string) => {
      setMessages((prev) => {
        const next = prev.slice();
        const last = next[next.length - 1];
        if (!last) return prev;
        next[next.length - 1] = {
          ...last,
          content: last.content + chunk,
        };
        return next;
      });
    };
    try {
      for await (const token of backend.stream(
        history,
        controller.signal,
      )) {
        setStatus("streaming");
        appendToReply(token);
      }
      if (controller.signal.aborted) {
        appendToReply(" [stopped]");
      }
      setStatus("idle");
    } catch (error) {
      if (controller.signal.aborted) {
        appendToReply(" [stopped]");
        setStatus("idle");
      } else {
        appendToReply(
          `[error: ${error instanceof Error ? error.message : String(error)}]`,
        );
        setStatus("error");
      }
    } finally {
      busyRef.current = false;
      abortRef.current = null;
    }
  };

  // Enter sends, Esc aborts. Key events bubble root → document, so the
  // listener lives on the document.
  useEffect(() => {
    if (!termUi) return;
    const doc = termUi.document;
    const onKey = (event: KeyboardEvent) => {
      if (event.type !== "keydown") return;
      if (
        event.key === "enter" &&
        !event.shiftKey
      ) {
        event.preventDefault();
        void send();
      } else if (event.key === "escape") {
        abortRef.current?.abort();
      }
    };
    doc.addEventListener("keydown", onKey);
    return () =>
      doc.removeEventListener("keydown", onKey);
  }, [termUi]);

  // seed the editable with a raw text node and place the caret in it
  // (JSX <text> children are text *elements*; setText gives the editable a
  // direct TextElement child the selection can anchor to)
  useEffect(() => {
    clearInput();
  }, [termUi]);

  // keep the newest message in view while streaming
  useEffect(() => {
    const history = historyRef.current;
    if (!history) return;
    history.scrollTo(0, history.scrollTopMax);
  }, [messages]);

  return (
    <view
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        padding: "0 1",
      }}
    >
      <text style={{ color: "gray" }}>
        {`term-ui chat · ${backend.label}`}
      </text>
      <view
        // biome-ignore lint/suspicious/noExplicitAny: view JSX types are SVG-typed today
        ref={historyRef as any}
        style={{
          width: "100%",
          flexGrow: 1,
          overflow: "scroll",
          borderStyle: "solid",
          borderColor: "gray",
          padding: "0 1",
        }}
      >
        {messages.length === 0 ? (
          <view style={{ padding: "0 1" }}>
            <text style={{ color: "gray" }}>
              Ask me anything - the conversation
              scrolls, the reply streams in
              live, and the input below is a
              real editable region (click to
              place the caret, drag to select).
            </text>
          </view>
        ) : (
          messages.map((message, index) => (
            <MessageRow
              // biome-ignore lint/suspicious/noArrayIndexKey: append-only list
              key={index}
              message={message}
            />
          ))
        )}
      </view>
      <InputBox inputRef={inputRef} />
      <text style={{ color: "gray" }}>
        {statusLabel[status]}
      </text>
    </view>
  );
};

await TermUi.createRoot(<App />, {});
