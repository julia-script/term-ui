import { applyWSSHandler } from "@trpc/server/adapters/ws";
import WebSocket, { WebSocketServer } from "ws";
import type { Document } from "../Document.js";
import { createRouter } from "./router.js";

export const devtools = (document: Document) => {
    const wss = new WebSocketServer({
      port: 3001,
    });
    const { router, ee } = createRouter(document);
    const handler = applyWSSHandler({
      wss,
      router,
      keepAlive: {
        enabled: true,
        pingMs: 30000,
        pongWaitMs: 5000,
      },
    });
    wss.on("connection", (ws) => {
      console.log(
        `Connection (${wss.clients.size})`,
      );
      ws.once("close", () => {
        console.log(
          `Connection (${wss.clients.size})`,
        );
      });
    });
    console.log(
      "✅ WebSocket Server listening on ws://localhost:3001",
    );
    process.on("SIGTERM", () => {
      console.log("SIGTERM");
      // handler.broadcastReconnectNotification();
      wss.close();
      // process.exit(0);
    });
    return {
      ee,
      dispose: () => {
        wss.close();
        // process.exit(0);
      },
    };
  };


export type { AppRouter } from "./router.js";