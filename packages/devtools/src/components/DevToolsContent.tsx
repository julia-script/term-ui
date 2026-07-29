import { useDevTools } from "./DevToolsContext";
import { DomTree } from "./DomTree";
import { Suspense } from "react";

export const DevToolsContent = () => {
  return (
    <view
      style={{
        display: "flex",
      }}
    >
      <Suspense
        fallback={
          <view>
            <text>Loading...</text>
          </view>
        }
      >
        <DomTree />
      </Suspense>
      
      {/* <text>DevTools</text> */}

      {/* <Suspense
        fallback={
          <term-view>
            <term-text>Loading...</term-text>
          </term-view>
        }
      > */}
      {/* </Suspense> */}
    </view>
  );
};
