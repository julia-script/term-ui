import crypto from "node:crypto";
import {
  Server,
  type Socket as SocketServer,
} from "socket.io";
import type { Socket as SocketClient } from "socket.io-client";
import * as v from "valibot";
import { traceSchema } from "./lib/trace";
const JsonRpcRequestSchema = v.object({
  jsonrpc: v.literal("2.0"),
  id: v.string(),
  method: v.string(),
  params: v.unknown(),
});

const JsonRpcResponseSchema = v.object({
  jsonrpc: v.literal("2.0"),
  id: v.string(),
  result: v.unknown(),
});
const JsonRpcErrorSchema = v.object({
  jsonrpc: v.literal("2.0"),
  id: v.string(),
  error: v.object({
    code: v.number(),
    message: v.string(),
    data: v.optional(v.unknown()),
  }),
});

const CHANNEL_NAME = "rpc";
export const defineProcedure = <
  Req extends v.GenericSchema,
  Res,
>(
  requestSchema: Req,
  handler: (params: {
    input: v.InferOutput<Req>;
  }) => Res,
) => {
  return {
    requestSchema,
    handler,
  };
};

type Procedure = ReturnType<
  typeof defineProcedure<never, never>
>;
type ProcedureMap = Record<string, Procedure>;

export const defineRouter = <
  const T extends ProcedureMap,
>(
  procedures: T,
) => {
  return {
    procedures,
  };
};

export type Router = ReturnType<
  typeof defineRouter
>;

export const createHost = <R extends Router>(
  socketOrServer: SocketClient | Server,
  router: R,
) => {
  const sockets = new Set<SocketServer>();

  const makeMessageHandler =
    (emit: (message: unknown) => void) =>
    (message: unknown) => {
      const { id, method, params } = v.parse(
        JsonRpcRequestSchema,
        message,
      );

      const procedure = router.procedures[method];
      if (!procedure) {
        emit({
          jsonrpc: "2.0",
          id,
          error: {
            code: -32601,
            message: "Method not found",
          },
        });
        return;
      }
      try {
        const input = v.safeParse(
          procedure.requestSchema,
          params,
        );
        if (!input.success) {
          emit({
            jsonrpc: "2.0",
            id,
            error: {
              code: -32602,
              message: "Invalid params",
              data: input.issues,
            },
          });
          return;
        }
        const result = procedure.handler({
          input: input.output,
        });

        socketOrServer.emit(CHANNEL_NAME, {
          jsonrpc: "2.0",
          id,
          result,
        });
      } catch (error) {
        if (error instanceof Error) {
          socketOrServer.emit(CHANNEL_NAME, {
            jsonrpc: "2.0",
            id,
            error: {
              code: -32602,
              message: error.message,
            },
          });
        } else {
          socketOrServer.emit(CHANNEL_NAME, {
            jsonrpc: "2.0",
            id,
            error: {
              code: -32602,
              message: "Internal error",
            },
          });
        }
      }
    };
  if (socketOrServer instanceof Server) {
    socketOrServer.on("connection", (socket) => {
      console.log("new connection", socket.id);
      socket.on(
        CHANNEL_NAME,
        makeMessageHandler((message) =>
          socket.emit(CHANNEL_NAME, message),
        ),
      );
      socket.on("disconnect", () => {
        console.log("disconnected", socket.id);
      });
    });
  } else {
    socketOrServer.on(
      CHANNEL_NAME,
      makeMessageHandler((message) =>
        socketOrServer.emit(
          CHANNEL_NAME,
          message,
        ),
      ),
    );
  }
  return {
    sockets,
    disconnect: () => {},
  };
};

export const createClient = <R extends Router>(
  socket: SocketClient | SocketServer,
) => {
  const rpcMap = new Map<
    string,
    [
      (params: unknown) => void,
      (error: Error) => void,
    ]
  >();
  const onMessage = (message: unknown) => {
    try {
      const response = v.parse(
        v.union([
          JsonRpcResponseSchema,
          JsonRpcErrorSchema,
        ]),
        message,
      );
      const resolver = rpcMap.get(response.id);
      if (resolver) {
        const [resolve, reject] = resolver;
        if ("error" in response) {
          reject(
            new Error(response.error.message),
          );
        } else {
          resolve(response.result);
        }
      }
    } catch (error) {
      console.error(error);
    }
  };
  socket.on(CHANNEL_NAME, onMessage);

  return {
    // socket,
    waitForConnection: () => {
      return new Promise<void>((resolve) => {
        const onConnect = () => {
          resolve();
        };
        socket.on("connect", onConnect);
      });
    },
    request: <T extends keyof R["procedures"]>(
      method: T,
      params: v.InferInput<
        R["procedures"][T]["requestSchema"]
      >,
      {
        signal = AbortSignal.timeout(5000),
      }: {
        signal?: AbortSignal;
      } = {},
    ) => {
      const id = crypto.randomUUID();
      const promise = new Promise<
        v.InferOutput<
          R["procedures"][T]["handler"]
        >
      >((resolve, reject) => {
        const onAbort = () => {
          cleanup();
          reject(new Error("Request timed out"));
        };
        const cleanup = () => {
          rpcMap.delete(id);
          signal.removeEventListener(
            "abort",
            onAbort,
          );
        };
        const onResolve = (result: unknown) => {
          cleanup();
          if (signal.aborted) return;
          resolve(result);
        };
        const onReject = (error: Error) => {
          cleanup();
          reject(error);
        };
        rpcMap.set(id, [onResolve, onReject]);
      });

      socket.emit(CHANNEL_NAME, {
        jsonrpc: "2.0",
        id,
        method,
        params,
      });
      return promise;
    },
  };
};
