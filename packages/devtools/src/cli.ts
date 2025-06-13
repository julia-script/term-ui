import {
  command,
  number,
  option,
  positional,
  run,
} from "cmd-ts";
import { DEFAULT_PORT } from "./constants";
import { startServer } from "./server";

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
  handler: ({ port }) => {
    console.log(port);
    startServer(port);
  },
});

// parse arguments
run(app, process.argv.slice(2));
