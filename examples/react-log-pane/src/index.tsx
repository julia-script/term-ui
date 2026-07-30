// The founding demo, multi-pane edition: independent scrollable sections
// that each respond to the mouse position. Wheel over a pane scrolls that
// pane; the nested box inside the right pane scrolls first and chains to
// its parent at the edge. The status line reports offsets via onScroll.
import TermUi from "@term-ui/react";
import {
  memo,
  useEffect,
  useState,
} from "react";

const levels = ["info", "warn", "debug"];
const messages = [
  "request handled in 12ms",
  "cache miss for key user:42",
  "reconnecting to upstream",
  "flushed 128 events",
  "config reloaded",
];

const line = (i: number) =>
  `[${levels[i % levels.length]}] #${i} ${messages[i % messages.length]}`;

// memoized: scroll-offset state updates must not re-render the row lists
const LogRows = memo(
  ({ count }: { count: number }) => (
    <>
      {Array.from({ length: count }, (_, i) => (
        <view key={i}>
          <text>{line(i)}</text>
        </view>
      ))}
    </>
  ),
);

const MetricRows = memo(() => (
  <>
    {Array.from({ length: 24 }, (_, i) => (
      <view key={i}>
        <text>{`metric ${i}: ${(i * 7) % 100}`}</text>
      </view>
    ))}
  </>
));

const NestedRows = memo(() => (
  <>
    {Array.from({ length: 12 }, (_, i) => (
      <view key={i}>
        <text>{`nested row ${i}`}</text>
      </view>
    ))}
  </>
));

const App = () => {
  const [count, setCount] = useState(200);
  const [offsets, setOffsets] = useState({
    logs: 0,
    metrics: 0,
    nested: 0,
  });
  useEffect(() => {
    const interval = setInterval(() => {
      setCount((n) => n + 1);
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  const report =
    (key: "logs" | "metrics" | "nested") =>
    // biome-ignore lint/suspicious/noExplicitAny: view props carry SVG types
    (event: any) =>
      setOffsets((prev) => ({
        ...prev,
        [key]: event.target.scrollTop,
      }));

  return (
    <view
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <text style={{ color: "gray" }}>
        offsets · logs {String(offsets.logs)} ·
        metrics {String(offsets.metrics)} ·
        nested {String(offsets.nested)}
      </text>
      <view style={{ display: "flex" }}>
        <view
          onScroll={report("logs")}
          style={{
            width: "44",
            height: "16",
            overflow: "scroll",
            borderStyle: "double",
            padding: "1",
            color: "white",
          }}
        >
          <LogRows count={count} />
        </view>
        <view
          onScroll={report("metrics")}
          style={{
            width: "30",
            height: "16",
            overflow: "scroll",
            borderStyle: "solid",
            padding: "1",
            color: "white",
          }}
        >
          <text>nested box:</text>
          <view
            onScroll={report("nested")}
            style={{
              width: "24",
              height: "4",
              overflow: "scroll",
              borderStyle: "double",
            }}
          >
            <NestedRows />
          </view>
          <MetricRows />
        </view>
      </view>
    </view>
  );
};

await TermUi.createRoot(<App />, {});
