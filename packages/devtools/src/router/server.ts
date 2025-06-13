import { inspect } from "node:util";
import * as v from "valibot";
import { traceSchema } from "../lib/trace";
import {
  defineProcedure,
  defineRouter,
} from "../rpc";

export const serverRouter = defineRouter({
  ping: defineProcedure(
    v.literal("ping"),
    ({ input }) => {
      console.log("ping");
      return "pong";
    },
  ),

  console: defineProcedure(
    v.object({
      level: v.union([
        v.literal("log"),
        v.literal("error"),
        v.literal("warn"),
        v.literal("info"),
        v.literal("debug"),
      ]),
      scope: v.string(),
      args: v.array(v.unknown()),
      trace: traceSchema,
    }),
    ({ input }) => {
      const args = input.args;

      const colors = {
        log: "\x1b[37m", // White
        error: "\x1b[31m", // Red
        warn: "\x1b[33m", // Yellow
        info: "\x1b[36m", // Cyan
        debug: "\x1b[35m", // Magenta
        reset: "\x1b[0m", // Reset
      };

      const levelColor =
        colors[input.level] || colors.log;
      const timestamp =
        new Date()
          .toISOString()
          .split("T")[1]
          ?.split(".")[0] ?? "";

      process.stdout.write(
        `\n${levelColor}[${timestamp}] [${input.level.toUpperCase()}] ${input.scope}${colors.reset}: `,
      );
      for (const arg of args) {
        if (typeof arg === "string") {
          process.stdout.write(`${arg} `);
        } else {
          process.stdout.write(
            `${inspect(arg, {
              depth: 10,
              colors: true,
            })} `,
          );
        }
      }
      return null;
    },
  ),
});

export type ServerRouter = typeof serverRouter;
