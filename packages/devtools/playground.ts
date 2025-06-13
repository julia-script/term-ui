import { io } from "socket.io-client";
import type { ServerRouter } from "./src/router/server";
import { createClient } from "./src/rpc";

const client = createClient<ServerRouter>(
  io("http://localhost:9001"),
);

const result = await client.request(
  "ping",
  "ping",
);
console.log(result);
