import { createServer } from "node:http";
import express from "express";
import { Server } from "socket.io";
import { serverRouter } from "./router/server";
import { createHost } from "./rpc";

export const startServer = (port: number) => {
  const app = express();
  const server = createServer(app);
  const io = new Server(server);
  io.on("connection", (socket) => {
    console.log("a user connected");
  });

  io.on("connection", (socket) => {
    console.log("a user connected");
  });

  const host = createHost(io, serverRouter);

  server.listen(port, () => {
    console.log(
      `server running at http://localhost:${port}`,
    );
  });
};
