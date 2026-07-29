import type { AppRouter } from "@term-ui/dom/devtools";
import type { TRPCClient } from "@trpc/client";
import { createContext, useContext } from "react";

export const DevToolsContext = createContext<{
  trpcClient: TRPCClient<AppRouter>;
} | null>(null);
export const useDevTools = () => {
  const context = useContext(DevToolsContext);
  if (!context) {
    throw new Error("useDevTools must be used within a DevToolsProvider");
  }
  return context;
};
