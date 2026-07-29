import type { AppRouter } from "@term-ui/dom/devtools";
import type { TRPCClient } from "@trpc/client";
import { TermUi } from "@term-ui/react";
import { DevToolsContext } from "./DevToolsContext";
import { DevToolsContent } from "./DevToolsContent";
import { ErrorBoundary } from "react-error-boundary";
import { QueryClientProvider } from '@tanstack/react-query'
import { queryClient } from "./queryClient";


export const DevTools = ({
  trpcClient,
}: {
  trpcClient: TRPCClient<AppRouter>;
}) => {
  return (
    <ErrorBoundary
      fallbackRender={(props) => (
        <view>
          <view>Error</view>
          <text>{props.error.message}</text>
        </view>
      )}
    >

      <DevToolsContext.Provider
        value={{ trpcClient }}
      >
        <QueryClientProvider client={queryClient}>
          <DevToolsContent />
        </QueryClientProvider>
        <view>Hello</view>
      </DevToolsContext.Provider>
    </ErrorBoundary>
  );
};
