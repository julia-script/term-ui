import { io } from "socket.io-client";
import { DEFAULT_PORT } from "./constants";

const createClient = ({
  url,
}: {
  url?: string;
}) => {
  const socket = io(
    url ?? `http://localhost:${DEFAULT_PORT}`,
  );
  const waitForConnection = new Promise<void>(
    (resolve, reject) => {
      const onConnect = () => {
        resolve();
        socket.off("connect", onConnect);
        socket.off("error", onError);
      };
      const onError = () => {
        reject(
          new Error(
            "Failed to connect to devtools",
          ),
        );
      };

      socket.on("connect", onConnect);
      socket.on("error", onError);
    },
  );

  const onConnect = () => {
    console.log("connected");
  };

  const onDisconnect = () => {
    console.log("disconnected");
  };

  socket.on("connect", onConnect);
  socket.on("disconnect", onDisconnect);

  const rpcMap = new Map<
    string,
    [
      resolve: (value: unknown) => void,
      reject: (reason?: Error) => void,
    ]
  >();

  return {
    socket,

    onConnect,
    onDisconnect,
    waitForConnection,
  };
};
