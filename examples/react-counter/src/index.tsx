import TermUi from "@term-ui/react";
import {
  type PropsWithChildren,
  useEffect,
  useState,
} from "react";
import type { ServerRouter } from "@termui/devtools/router/server";
import { createClient } from "@termui/devtools/rpc";
import { io } from "socket.io-client";

const App = () => {
  const [count, setCount] = useState(3);
  useEffect(() => {
    // setCount(count + 1)
    const interval = setInterval(() => {
      setCount((count) => count + 1);
    }, 1000);
    return () => clearInterval(interval);
  }, []);
  return (
    <view
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        // overflow: "scroll",
        padding: "1",
        // backgroundColor:
        //   "radial-gradient(circle at top left,rgba(10, 10, 10, 1), rgba(252, 70, 107, .05))",
      }}
    >
      {/* <text>{count}</text> */}
      {new Array(count)
        .fill(0)
        .map((_, index) => (
          <view
            key={index}

            style={{
              width: "1",
              height: "1",

              // backgroundColor: "white",
            }}
          >
            <text>Hello</text>
          </view>
        ))}
    </view>
  );
};

await TermUi.createRoot(<App />, {});
