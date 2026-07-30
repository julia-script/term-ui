// The founding demo: a scrollable log pane in the middle of the terminal.
// Wheel and PgUp/PgDn scroll it; text inside is selectable with the mouse;
// a ticker appends lines to prove repaint + scroll position stability.
import TermUi from "@term-ui/react";
import { useEffect, useState } from "react";

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

const App = () => {
  const [count, setCount] = useState(200);
  useEffect(() => {
    const interval = setInterval(() => {
      setCount((n) => n + 1);
    }, 1000);
    return () => clearInterval(interval);
  }, []);

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
        wheel / PgUp / PgDn to scroll · drag to
        select · {String(count)} lines
      </text>
      <view
        style={{
          width: "60",
          height: "14",
          overflow: "scroll",
          borderStyle: "double",
          padding: "1",
          color: "white",
        }}
      >
        {Array.from({ length: count }, (_, i) => (
          <view key={i}>
            <text>{line(i)}</text>
          </view>
        ))}
      </view>
    </view>
  );
};

await TermUi.createRoot(<App />, {});
