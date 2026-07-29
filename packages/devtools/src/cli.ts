import {
  command,
  number,
  option,
  positional,
  run,
} from "cmd-ts";
import {
  createTRPCClient,
  createWSClient,
  wsLink,
} from "@trpc/client";
import type { AppRouter } from "@term-ui/dom/devtools";
import { DEFAULT_PORT } from "./constants";
import { DevTools } from "./components/DevTools.js";
import { TermUi } from "@term-ui/react";

const app = command({
  name: "devtools",
  args: {
    port: option({
      type: number,
      long: "port",
      short: "p",
      description: "Port to listen on",
      defaultValue: () => DEFAULT_PORT,
    }),
  },
  handler: async ({ port }) => {
    console.log(port);
    // startServer(port);
    const wsClient = createWSClient({
      url: `ws://localhost:${port}`,
    });
    const trpcClient =
      createTRPCClient<AppRouter>({
        links: [
          wsLink<AppRouter>({ client: wsClient }),
        ],
      });

    const status = await trpcClient.status.query(
      undefined,
      {
        signal: AbortSignal.timeout(5000),
      },
    );
    // console.log(status);
    const nodeInfo =
      await trpcClient.getNodeInfo.query(
        status.root,
      );
    trpcClient.onRender.subscribe(undefined, {
      onData: async (data) => {
        const dump = await trpcClient.getDump.query();
        console.log(dump.data);
        
      },
    
      onError(error) {
        console.error(error);
      },
      onComplete() {
        console.log("complete");
      },
    }); 
    // setInterval(async () => {
    //   const dump =
    //     await trpcClient.getDump.query();
    //   console.log(dump.data);
    // }, 1000);

    console.log(nodeInfo);
    // await TermUi.createRoot(
    //   DevTools({
    //     trpcClient,
    //   }),
    //   {
    //     dev: false,
    //   },
    // );

    // console.log(nodeInfo);
  },
});

// parse arguments
run(app, process.argv.slice(2));
